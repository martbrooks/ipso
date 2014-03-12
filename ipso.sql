BEGIN;

DROP TABLE IF EXISTS ipblocks CASCADE;
DROP TABLE IF EXISTS ipallocations CASCADE;
DROP TABLE IF EXISTS hosts CASCADE;

set role ipso;

CREATE TABLE IF NOT EXISTS ipblocks (
	blockid serial primary key,
	ipblock cidr NOT NULL,
	ipblockfamily int,
	note varchar,
	created timestamp with time zone default now(),
	changed timestamp with time zone default now()
);

CREATE TABLE IF NOT EXISTS ipallocations (
	allocid serial primary key,
	blockid bigint references ipblocks (blockid) ON DELETE CASCADE,
	firstip inet NOT NULL,
	ipcount bigint NOT NULL,
	note varchar,
	created timestamp with time zone default now(),
	changed timestamp with time zone default now()
);

CREATE TABLE IF NOT EXISTS hosts (
	hostid SERIAL PRIMARY KEY,
	blockid BIGINT REFERENCES ipblocks (blockid) ON DELETE CASCADE,
	allocid BIGINT REFERENCES ipallocations (allocid) ON DELETE CASCADE,
	ip INET NOT NULL,
	hostname VARCHAR NOT NULL,
	note VARCHAR,
	created timestamp with time zone default now(),
	changed timestamp with time zone default now()
);

DROP FUNCTION IF EXISTS create_ip_allocation();
CREATE OR REPLACE FUNCTION create_ip_allocation() RETURNS TRIGGER AS
$$
DECLARE
    iterator INT;
    ip_block CIDR;
    existing RECORD;
BEGIN
    IF NEW.firstip IS NULL THEN
        RAISE EXCEPTION 'firstip cannot be null';
    END IF;
    IF NEW.ipcount IS NULL THEN
        RAISE EXCEPTION 'firstip cannot be null';
    END IF;

    SELECT ipblock FROM ipblocks WHERE blockid = NEW.blockid INTO ip_block;

    IF NOT ip_block >> (NEW.firstip + NEW.ipcount)::INET THEN
        RAISE EXCEPTION 'Last IP % exceeds block range %', NEW.firstip + NEW.ipcount, ip_block;
    END IF;

    FOR existing IN SELECT allocid, firstip, ipcount FROM ipallocations WHERE blockid = NEW.blockid LOOP
        IF (TG_OP = 'UPDATE') AND existing.allocid = OLD.allocid THEN
                -- DO NOTHING - this is the row being replaced
        ELSE
            FOR iterator IN 0..NEW.ipcount LOOP
                IF existing.firstip <= (NEW.firstip + iterator)::INET AND
                   (existing.firstip + existing.ipcount)::INET >= (NEW.firstip + iterator)::INET THEN
                    RAISE EXCEPTION 'Range overlap: % - % overlaps existing % - %', NEW.firstip, (NEW.firstip + NEW.ipcount)::INET, existing.firstip, (existing.firstip + existing.ipcount)::INET;
                END IF;
            END LOOP;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS update_ip_block_family();
CREATE FUNCTION update_ip_block_family() RETURNS TRIGGER AS
$$ 
BEGIN
    NEW.ipblockfamily:=family(NEW.ipblock);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS update_last_changed();
CREATE FUNCTION update_last_changed() RETURNS TRIGGER AS
$$ 
BEGIN
    NEW.changed:=now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ipallocations_ranges BEFORE INSERT OR UPDATE OF firstip, ipcount ON ipallocations FOR EACH ROW EXECUTE PROCEDURE create_ip_allocation();

CREATE TRIGGER trigger_ipblocks_family BEFORE INSERT OR UPDATE OF ipblock ON ipblocks FOR EACH ROW EXECUTE PROCEDURE update_ip_block_family();
CREATE TRIGGER ipblocks_changed BEFORE INSERT OR UPDATE OF ipblock,note ON ipblocks FOR EACH ROW EXECUTE PROCEDURE update_last_changed();
CREATE TRIGGER ipallocations_changed BEFORE INSERT OR UPDATE OF firstip,ipcount,note ON ipallocations FOR EACH ROW EXECUTE PROCEDURE update_last_changed();
CREATE TRIGGER hosts_changed BEFORE INSERT OR UPDATE OF ip,hostname,note ON hosts FOR EACH ROW EXECUTE PROCEDURE update_last_changed();

CREATE OR REPLACE VIEW ipblock_allocations AS
	SELECT ipallocations.blockid, ipallocations.allocid, ipblocks.ipblock, ipblocks.ipblockfamily, ipallocations.firstip, ipallocations.firstip + ipallocations.ipcount AS lastip,
	ipallocations.ipcount,(SELECT COUNT(ip) FROM hosts WHERE hosts.allocid=ipallocations.allocid) AS used,ipallocations.note
	FROM ipblocks,ipallocations,hosts
	WHERE ipallocations.blockid = ipblocks.blockid
	GROUP BY ipallocations.allocid,ipblocks.ipblock,ipblocks.ipblockfamily
	ORDER BY ipallocations.blockid ASC;

INSERT INTO ipblocks (ipblock,note) VALUES ('192.168.0.0/24','Part of RFC1918');
INSERT INTO ipblocks (ipblock,note) VALUES ('192.168.1.0/24','Part of RFC1918');
INSERT INTO ipblocks (ipblock,note) VALUES ('10.0.0.0/8','Also part of RFC1918');
INSERT INTO ipblocks (ipblock,note) VALUES ('2001:ba8:1f1:f12c::/64','Some IPv6');

INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (1,'192.168.0.123',10,'ACME Widgets allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (1,'192.168.0.10',30,'ACME Traps allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (2,'192.168.1.1',10,'ACME Widgets allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (2,'192.168.1.100',30,'ACME Traps allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (3,'10.119.48.20',10,'29HC network devices');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (4,'2001:ba8:1f1:f12c::2',100000,'ACME Traps v6 allocation');

INSERT INTO hosts (blockid,allocid,ip,hostname,note) VALUES (3,5,'10.119.48.20','core-29hc','29HC core switch');
INSERT INTO hosts (blockid,allocid,ip,hostname,note) VALUES (3,5,'10.119.48.21','office-29hc','29HC office 8 port switch');
INSERT INTO hosts (blockid,allocid,ip,hostname,note) VALUES (3,5,'10.119.48.22','media-29hc','29HC media room 8 port switch');
INSERT INTO hosts (blockid,allocid,ip,hostname,note) VALUES (3,5,'10.119.48.23','bedroom-29hc','29HC bedroom 8 port switch');

COMMIT;
