drop table if exists ipblocks CASCADE;
drop table if exists ipallocations CASCADE;

set role ipso;

create table if not exists ipblocks (
	blockid serial primary key,
	ipblock cidr NOT NULL,
	ipblockfamily int,
	note varchar
);

create table if not exists ipallocations (
	allocid serial primary key,
	blockid bigint references ipblocks (blockid) NOT NULL,
	firstip inet NOT NULL,
	ipcount bigint NOT NULL,
	note varchar
);

DROP FUNCTION IF EXISTS update_ip_block_family();
CREATE FUNCTION update_ip_block_family() RETURNS TRIGGER AS
$$ 
BEGIN
    NEW.ipblockfamily:=family(NEW.ipblock);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ipblock_family BEFORE INSERT OR UPDATE OF ipblock ON ipblocks FOR EACH ROW EXECUTE PROCEDURE update_ip_block_family();

CREATE OR REPLACE VIEW ipblock_allocations AS
	SELECT ipallocations.blockid,allocid,ipblocks.ipblock,firstip,firstip+ipcount AS lastip,ipcount,ipallocations.note
	FROM ipblocks,ipallocations
	WHERE ipallocations.blockid=ipblocks.blockid
	ORDER BY blockid ASC;

INSERT INTO ipblocks (ipblock,note) VALUES ('192.168.0.0/24','Part of RFC1918');
INSERT INTO ipblocks (ipblock,note) VALUES ('192.168.1.0/24','Part of RFC1918');
INSERT INTO ipblocks (ipblock,note) VALUES ('10.0.0.0/8','Also part of RFC1918');
INSERT INTO ipblocks (ipblock,note) VALUES ('2001:ba8:1f1:f12c::/64','Some IPv6');

INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (1,'192.168.0.123',10,'ACME Widgets allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (1,'192.168.0.10',30,'ACME Traps allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (2,'192.168.1.1',10,'ACME Widgets allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (2,'192.168.1.100',30,'ACME Traps allocation');
INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES (4,'2001:ba8:1f1:f12c::2',100000,'ACME Traps v6 allocation');
