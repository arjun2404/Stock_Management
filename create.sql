
    drop table IF EXISTS trade;
    drop table IF EXISTS daywiseStock;
    drop table IF EXISTS stock;
    drop table IF EXISTS manages;
    drop table IF EXISTS works;
    drop table IF EXISTS portfolio;
    drop table IF EXISTS trader;
    drop table IF EXISTS manager;

    create table manager 
    (
        M_ID varchar(8),
        name varchar(30) not null,
        address varchar(40),
        primary key (M_ID)
    );
    create table trader 
    (
        T_ID varchar(8),
        name varchar(30) not null,
        address varchar(40),
        primary key (T_ID)
    );
    create table portfolio
    (
        P_ID varchar(8),
        PortfolioName varchar(30) not null,
        AssetValue numeric(8,2) check (AssetValue > 0),
        primary key (P_ID)
    );
    create table works
    (
        M_ID varchar(8),
        T_ID varchar(8),
        primary key (M_ID, T_ID),
        foreign key (M_ID) references manager (M_ID)
            on delete cascade,
        foreign key (T_ID) references trader (T_ID)
            on delete cascade
    );
    create table manages
    (
        M_ID varchar(8),
        P_ID varchar(8),
        primary key (M_ID, P_ID),
        foreign key (M_ID) references manager (M_ID)
            on delete cascade,
        foreign key (P_ID) references portfolio (P_ID)
            on delete cascade
    );
    create table stock(
        Symbol varchar(20),
        Rank numeric(4,0),
        Company varchar(100),
        Country varchar(20),
        Sales numeric(8,0),
        MarketValues numeric(8,0),
        Profit numeric(8,0),
        Assests numeric(8,0),
        Sector varchar(50),
        primary key (Symbol)
    );

    create table daywiseStock(
        Symbol varchar(20),
        Opening numeric(10,2),
        Ask numeric(10,2),
        Bid numeric(10,2),
        Closing numeric(10,2),
        primary key (Symbol),
        foreign key (Symbol) references Stock (Symbol) 
            on delete cascade
    );

    create table trade(
    Trade_ID varchar(8),
    T_ID varchar(8),
    Symbol varchar(20),
    Amount numeric(10,2),
    Action varchar(8) check (Action in ('BUY','SELL')),
    Price numeric(10,2),
    P_ID varchar(8),
    M_ID varchar(8),
    PL numeric(10,2),
    Performance varchar(20),
    Decision varchar(20),
    primary key (Trade_ID),
    foreign key (Symbol) references Stock (Symbol) 
            on delete cascade,
    foreign key (M_ID) references manager (M_ID)
        on delete cascade,
    foreign key (P_ID) references portfolio (P_ID)
        on delete cascade,
    foreign key (T_ID) references trader (T_ID)
        on delete cascade
    );

    -- --Symbol index on daywise stock
    DROP INDEX IF EXISTS idx_daywisestock_symbol;
    -- CREATE INDEX idx_daywisestock_symbol
    -- ON daywisestock(symbol);

    -- Pl Trigger

    DROP TRIGGER IF EXISTS update_pl ON trade;
    DROP FUNCTION IF EXISTS calculate_pl();


    CREATE FUNCTION calculate_pl() RETURNS trigger AS $calculate_pl$
        DECLARE closing_var NUMERIC(10,2);
        DECLARE pl_var NUMERIC(10,2);
        BEGIN
            select closing into closing_var FROM
            daywiseStock where Symbol=NEW.Symbol;

            IF closing_var IS NULL THEN
                RAISE EXCEPTION 'The symbol: % does not have a closing value', NEW.Symbol;
            END IF;

            -- calculating profit based on action
            IF NEW.action = 'BUY' THEN
                pl_var := NEW.amount * (closing_var-NEW.price);
            END IF;
            IF NEW.action = 'SELL' THEN
                pl_var := NEW.amount * (NEW.price - closing_var);
            END IF;
            NEW.pl = pl_var;

            NEW.decision := 'PROFIT';
            
            IF pl_var > 0 THEN
                NEW.decision := 'LOSS';
            END IF;
            RETURN NEW;
        END;
    $calculate_pl$ LANGUAGE plpgsql;

    CREATE TRIGGER update_pl BEFORE INSERT OR UPDATE ON trade
        FOR EACH ROW EXECUTE FUNCTION calculate_pl();


    -- STORED PROC (UPDATE_PORTFOLIOS)
    -- at the end of trade day, after pl are calculated for every trade
    -- we execute this stored proc to add pl values in to respective portfolio and update their asset values
    -- if a certain portfolio is incurring losses we raise a notice

    DROP PROCEDURE IF EXISTS UPDATE_PORTFOLIOS;
    CREATE OR REPLACE PROCEDURE UPDATE_PORTFOLIOS() LANGUAGE PLPGSQL AS $$
    declare cur_trades cursor for select p_id, sum(pl) as net_pl from trade group by p_id;
    groupRec RECORD;
    assetvalue_var portfolio.assetvalue%TYPE;
    begin
        open cur_trades;
        loop
            fetch cur_trades into groupRec;
            exit when not found;
            RAISE NOTICE 'Calling cs_create_job(%)(%)',groupRec.p_id, groupRec.net_pl;
            select assetvalue into assetvalue_var
            from portfolio
            where p_id = groupRec.p_id;
            if groupRec.net_pl+assetvalue_var <0 then
                RAISE NOTICE 'Portfolio incurring losses is (%)(%)',groupRec.p_id, groupRec.net_pl;
            else
                update portfolio
                set assetvalue = assetvalue+groupRec.net_pl
                where p_id = groupRec.p_id;
            END if;
        end loop;
        commit;
    end;$$;