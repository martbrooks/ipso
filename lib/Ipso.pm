use strict;
use warnings;
use DBD::Pg;
use Data::Dumper;
use IO::Prompt;
use Switch;
use Regexp::Common qw /net/;
use Regexp::Common::net::CIDR ();
use Regexp::IPv6 qw($IPv6_re);

sub dbconnect{
	my $dbname='ipso';
	my $host='localhost';
	my $port=5432;
	my $options='';
	my $username='ipso';
	my $password='ipso';
	my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",$username,$password,
		{AutoCommit => 1, RaiseError => 1, PrintError => 0}
	);
	return $dbh;
}

sub fetchrows_as_hash{
	my ($dbh,$sql,$key)=@_;
	my $sth = $dbh->prepare("$sql");
	$sth->execute;
	my $tmp=$sth->fetchall_hashref($key);
	return %{$tmp};
}

sub getBlockInfo{
	my $dbh=dbconnect();
	my %ipblocks=fetchrows_as_hash($dbh,'SELECT blockid,ipblock,ipblockfamily,note,EXTRACT(EPOCH FROM now()-changed) as age FROM ipblocks',1);
	foreach my $record (keys %ipblocks){
		my ($block,$mask)=split/\//,$ipblocks{$record}{ipblock};
		switch ($ipblocks{$record}{ipblockfamily}) {
			case 4 { $ipblocks{$record}{maxips}=2**(32-$mask);  }
			case 6 { $ipblocks{$record}{maxips}=2**(128-$mask); }
		}
	}
	my %ipallocations=fetchrows_as_hash($dbh,'SELECT ipblocks.blockid,COUNT(ipcount) AS allocations,SUM(ipcount) AS allocated FROM ipblocks,ipallocations WHERE ipblocks.blockid=ipallocations.blockid GROUP BY ipblocks.blockid',1);
	foreach my $record (keys %ipallocations){
		my $blockid=$ipallocations{$record}{blockid};
		$ipblocks{$blockid}{allocations}=$ipallocations{$record}{allocations};
		$ipblocks{$blockid}{allocated}=$ipallocations{$record}{allocated};
	}
	$dbh->disconnect;
	return %ipblocks;
}

sub addIPBlock{
	my ($newblock,$note)=@_;
	my $dbh=dbconnect();
	my %overlap=fetchrows_as_hash($dbh,"SELECT ipblock FROM ipblocks WHERE '$newblock' <<= ipblock OR '$newblock' >>= ipblock",1);
	my @overlaps=();
	foreach my $ipblock (keys %overlap){
		push @overlaps,$ipblock;
	}
	my $overlapcount=scalar @overlaps;
	if ($overlapcount>0){
		print "Error: IP block $newblock overlaps $overlapcount existing IP block";
		if ($overlapcount>1){
			print "s";
		}
		print ": " . join (", ",@overlaps) . "\n";
		exit;
	}
	$dbh->do("INSERT INTO ipblocks (ipblock,note) VALUES ('$newblock','$note')");
	$dbh->disconnect;
	print "Block added.\n";
}

sub deleteIPBlock{
	exit unless are_you_sure("Deleting an IP block will remove all dependent allocations and hosts.\n");
	my $block=shift;
	my $sql='DELETE FROM ipblocks WHERE ';
	if (is_ipv4_cidr($block) || is_ipv6_cidr($block)){
		$sql.="ipblock = '$block'";
	} else {
		$sql.="blockid = '$block'";
	}
	my $dbh=dbconnect();
	$dbh->do($sql);
	$dbh->disconnect;
	print "Block removed.\n";
}

sub mapIPBlock{
	my $blockid=shift;
	my $dbh=dbconnect();
	my $block='';
	my $topip='';
	my %allocs=fetchrows_as_hash($dbh,"SELECT row_number() OVER (ORDER BY firstip) AS id,ipblock,(firstip-1)::inet AS previp,firstip,lastip,COALESCE((lag(lastip+1) over (order by lastip)),host(ipblock)::inet) as lastlastip,COALESCE((firstip-(LAG(lastip) OVER (ORDER BY firstip))::inet-1),(firstip-ipblock)) AS gap,ipcount,used,note FROM ipblock_allocations WHERE blockid=$blockid ORDER BY firstip",1);

	foreach my $thisalloc (sort keys %allocs){
		my $firstip=$allocs{$thisalloc}{firstip};
		my $lastip=$allocs{$thisalloc}{lastip};
		my $gap=$allocs{$thisalloc}{gap};
		my $lastlastip=$allocs{$thisalloc}{lastlastip};
		my $previp=$allocs{$thisalloc}{previp};
		my $ipcount=$allocs{$thisalloc}{ipcount};
		if ($gap!=0){
			print "GAP : ";
			print "$lastlastip -> $previp: $gap\n";
		}
		print "RANGE : $firstip -> $lastip: $ipcount\n";
		$block=$allocs{$thisalloc}{ipblock};
		$topip=$lastip;
	}
	my %tmp=fetchrows_as_hash($dbh,"SELECT 1 AS id,'$topip'::inet+1 AS nextip,host(broadcast('$block')::inet) as lastip,broadcast('$block')-'$topip'::inet AS ipcount",1);
	print "GAP: $tmp{1}{nextip} -> $tmp{1}{lastip}: $tmp{1}{ipcount}\n";
}

sub getAllocationInfo{
	my %allocinfo=();
	my $block=shift;
	my $sql='SELECT allocid,ipblock,ipblockfamily,firstip,lastip,ipcount,used,note,age FROM ipblock_allocations';
	if (is_ipv4_cidr($block) || is_ipv6_cidr($block)){
		$sql.=" WHERE ipblock = '$block'";
	} elsif ($block ne 'all'){
		$sql.=" WHERE blockid = '$block'";
	}
	my $dbh=dbconnect();
	my %allocations=fetchrows_as_hash($dbh,$sql,1);
	if (scalar keys %allocations == 0){
		print "No allocations found.\n";
		exit;
	}
	$dbh->disconnect;
	return %allocations;
}

sub deleteIPAllocation{
	exit unless are_you_sure("Deleting an IP allocation will remove all host IP assignments that it contains.\n");
	my $block=shift;
	my $dbh=dbconnect();
	$dbh->do("DELETE FROM ipallocations WHERE allocid=$block");
	$dbh->disconnect;
	print "Allocation removed.\n";
}

sub addIPAllocation{
	my ($firstip,$ipcount,$note)=@_;
	my %blockinfo=getBlockInfo();
	my $dbh=dbconnect();
	$dbh->begin_work;
	$dbh->do('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
	my %tmp=fetchrows_as_hash($dbh,"SELECT blockid FROM ipblocks WHERE '$firstip' << ipblock",1);
	if (scalar keys %tmp!=1){
		print "Error: No unique block identified to contain $firstip.\n";
	}
	my $tmpkey=(keys %tmp)[0];
	my $blockid=$tmp{$tmpkey}{blockid};
	my %allocinfo=getAllocationInfo($blockid);
	$dbh->do('CREATE TEMPORARY TABLE range_overlaps (id BIGINT DEFAULT NULL,existing INET DEFAULT NULL,proposed INET DEFAULT NULL)');
	$dbh->do('CREATE INDEX idx_existing ON range_overlaps(existing)');
	$dbh->do('CREATE INDEX idx_proposed ON range_overlaps(proposed)');
	foreach my $thisalloc (keys %allocinfo){
		my $allocid=$allocinfo{$thisalloc}{allocid};
		my $start=$allocinfo{$thisalloc}{firstip};
		my $count=$allocinfo{$thisalloc}{ipcount};
		for (my $i=0;$i<=$count;$i++){
			$dbh->do("INSERT INTO range_overlaps (id,existing) VALUES ($allocid,'$start'::inet+$i)");
		}
	}
	for (my $i=0;$i<$ipcount;$i++){
		$dbh->do("INSERT INTO range_overlaps (proposed) VALUES ('$firstip'::inet+$i)");
	}
	$dbh->do('ANALYZE range_overlaps');
	my %overlaps=fetchrows_as_hash($dbh,'SELECT DISTINCT (a.id) from range_overlaps AS a,range_overlaps AS b WHERE a.existing=b.proposed',1);
	if (scalar keys %overlaps>0){
		print "Error: Requested range overlaps existing allocations: ";
		my @ranges=();
		foreach my $overlap (keys %overlaps){
			push @ranges,"$allocinfo{$overlap}{firstip}-$allocinfo{$overlap}{lastip}";
		}
		print join (", ",@ranges) . "\n";
	} else {
		$dbh->do("INSERT INTO ipallocations (blockid,firstip,ipcount,note) VALUES ($blockid,'$firstip',$ipcount,'$note')");
		$dbh->commit;
		print "IP allocation added.\n";
	}
	$dbh->disconnect;
}

sub are_you_sure{
	my $info=shift || '';
	if ($info){
		print "$info";
	}
	my $response=prompt("Are you sure (y/n)? ", -yn);
	$response=lc(substr($response,0,1));
	return $response eq 'y'?1:0;
}

sub is_ipblock_identifier{
	my $block=shift;
	return $block=~/^\d+$/ || is_ipv4_cidr($block) || is_ipv6_cidr($block);
}

sub is_ipv4_address{
	my $ip=shift;
	return $ip =~ $RE{net}{IPv4}?1:0;
}

sub is_ipv4_cidr{
	my $cidr=shift;
	return $cidr =~ $RE{net}{CIDR}{IPv4}?1:0;
}

sub is_ipv6_address{
	my $ip=shift;
	return $ip =~ $RE{net}{IPv6}?1:0;
}

# This regex taken from
# http://blog.markhatton.co.uk/2011/03/15/regular-expressions-for-ip-addresses-cidr-ranges-and-hostnames/
sub is_ipv6_cidr{
	my $cidr=shift;
	return $cidr =~ /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*(\/(\d|\d\d|1[0-1]\d|12[0-8]))$/?1:0;
}

1;
