use strict;
use warnings;
use DBD::Pg;
use Data::Dumper;
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
	my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",$username,$password
		# {AutoCommit => 0, RaiseError => 1, PrintError => 0}
	);
	return $dbh;
}

sub handle_simple_select{
	my $dbh=shift;
	my $sql=shift;
	my $sth = $dbh->prepare("$sql");
	if ( !defined $sth ) {
		die "Cannot prepare statement: $DBI::errstr\n";
	}
	$sth->execute;
	my $rows=$sth->fetchall_arrayref();
	return $rows;
}

sub handle_simple_insert{
	my $dbh=shift;
	my $sql=shift;
	my $sth = $dbh->prepare("$sql");
	if ( !defined $sth ) {
		die "Cannot prepare statement: $DBI::errstr\n";
	}
	$sth->execute;
}

sub getBlockInfo{
	my %ipblockinfo=();
	my $dbh=dbconnect();
	my $ipblocks=handle_simple_select($dbh,'SELECT blockid,ipblock,ipblockfamily,note FROM ipblocks');
	foreach my $thisblock (@{$ipblocks}){
		my $blockid=$thisblock->[0];
		$ipblockinfo{$blockid}{ipblock}=$thisblock->[1];
		$ipblockinfo{$blockid}{ipfamily}=$thisblock->[2];
		my ($block,$mask)=split/\//,$ipblockinfo{$blockid}{ipblock};
		switch ($ipblockinfo{$blockid}{ipfamily}) {
			case 4 { $ipblockinfo{$blockid}{maxips}=2**(32-$mask);  }
			case 6 { $ipblockinfo{$blockid}{maxips}=2**(128-$mask); }
		}
		$ipblockinfo{$blockid}{note}=$thisblock->[3];
	}
	my $ipallocations=handle_simple_select($dbh,'SELECT ipblocks.blockid,COUNT(ipcount),SUM(ipcount) FROM ipblocks,ipallocations WHERE ipblocks.blockid=ipallocations.blockid GROUP BY ipblocks.blockid ORDER BY ipblocks.blockid');
	foreach my $thisallocation (@{$ipallocations}){
		my $blockid=$thisallocation->[0];
		$ipblockinfo{$blockid}{allocations}=$thisallocation->[1];
		$ipblockinfo{$blockid}{allocated}=$thisallocation->[2];
	}
	$dbh->disconnect;
	return %ipblockinfo;
}

sub addIPBlock{
	my $newblock=shift;
	my $note=shift;
	my $dbh=dbconnect();
	my $overlap=handle_simple_select($dbh,"SELECT ipblock FROM ipblocks WHERE '$newblock' <<= ipblock OR '$newblock' >>= ipblock");
	my @overlaps=();
	foreach my $ipblock (@{$overlap}){
		push @overlaps,$ipblock->[0];
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
	handle_simple_insert($dbh,"INSERT INTO ipblocks (ipblock,note) VALUES ('$newblock','$note')");
	print "Block added.\n";
}

sub getAllocationInfo{
	my %allocinfo=();
	my $block=shift;
	my $sql='SELECT allocid,ipblock,firstip,lastip,ipcount,used,note FROM ipblock_allocations';
	if (is_ipv4_cidr($block) || is_ipv6_cidr($block)){
		$sql.=" WHERE ipblock = '$block'";
	} elsif ($block ne 'all'){
		$sql.=" WHERE blockid = '$block'";
	} else {
		$sql.=' ORDER BY allocid ASC';
	}
	my $dbh=dbconnect();
	my $allocations=handle_simple_select($dbh,$sql);
	my $ipblock='';
	foreach my $thisalloc (@{$allocations}){
		my $allocid=$thisalloc->[0];
		$ipblock=$thisalloc->[1];
		$allocinfo{$allocid}{firstip}=$thisalloc->[2];
		$allocinfo{$allocid}{lastip}=$thisalloc->[3];
		$allocinfo{$allocid}{ipcount}=$thisalloc->[4];
		$allocinfo{$allocid}{used}=$thisalloc->[5];
		$allocinfo{$allocid}{note}=$thisalloc->[6];
	}
	$dbh->disconnect;
	if (scalar keys %allocinfo == 0){
		print "No allocations found.\n";
		exit;
	}
	return ($ipblock,%allocinfo);
}


sub is_ipv4_address{
	my $ip=shift;
	if ($ip =~ $RE{net}{IPv4}){
		return 1;
	} else {
		return 0;
	}
}

sub is_ipv4_cidr{
	my $cidr=shift;
	if ($cidr =~ $RE{net}{CIDR}{IPv4}){
		return 1;
	} else {
		return 0;
	}
}

sub is_ipv6_address{
	my $ip=shift;
	if ($ip =~ $RE{net}{IPv6}){
		return 1;
	} else {
		return 0;
	}
}

# This regex taken from
# http://blog.markhatton.co.uk/2011/03/15/regular-expressions-for-ip-addresses-cidr-ranges-and-hostnames/

sub is_ipv6_cidr{
	my $cidr=shift;
	if ($cidr =~ /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*(\/(\d|\d\d|1[0-1]\d|12[0-8]))$/){
		return 1;
	} else {
		return 0;
	}
}

1;
