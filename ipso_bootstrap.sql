BEGIN;

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
