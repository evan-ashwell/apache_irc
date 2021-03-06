#!/usr/bin/perl
## This program is free software; you can redistribute it
## and/or modify it under the same terms as Perl itself.
## Please see the Perl Artistic License 2.0.
## 
## Copyright (C) 2004-2015 Megan Squire <msquire@elon.edu>
##
## We're working on this at http://flossmole.org - Come help us build 
## an open and accessible repository for data and analyses for open
## source projects.
##
## If you use this code or data for preparing an academic paper please
## provide a citation to 
##
## Howison, J., Conklin, M., & Crowston, K. (2006). FLOSSmole: 
## A collaborative repository for FLOSS research data and analyses. 
## International Journal of Information Technology and Web Engineering, 1(3), 17–26.
##
## and
##
## FLOSSmole (2004-2015) FLOSSmole: a project to provide academic access to data 
## and analyses of open source projects.  Available at http://flossmole.org 
#
################################################################
# usage:
# > perl 2parseActiveMQIRCLogs.pl <datasource_id> 
#
# example usage:
# > perl 2parseActiveMQIRCLogs.pl 48483 
#
# purpose: 
# open each IRC log in the directory, parse out the interesting bits
# notes:
# START WITH THE FIRST DS IN THE DB YOU ARE INTERESTED IN
# Does not need to be the latest one
#
################################################################
use strict;
use DBI;
use HTML::Entities;

my $datasource_id = shift @ARGV;
my $forge_id = 36;

if ($datasource_id)
{
	# connect to db (twice at local and once remote)
	# dsn takes the format of "DBI:mysql:ossmole_merged:hostname"
	my $dsn1 = "DBI:mysql:ossmole_merged:hostname";
	my $dbh1 = DBI->connect($dsn1, "username", "password", {RaiseError=>1});
	
	my $dsn2 = "DBI:mysql:apache_irc:hostname";
	my $dbh2 = DBI->connect($dsn2, "username", "password", {RaiseError=>1});
	
	my $dsn3 = "DBI:mysql:apache_irc:hostname";
	my $dbh3 = DBI->connect($dsn3, "username", "password", {RaiseError=>1});
	
	# get the file list from the 'comments' field in the datasources table
	my $sth1 = $dbh1->prepare(qq{select datasource_id, comments 
		from ossmole_merged.datasources 
		where datasource_id >= ? 
		and forge_id=?});
    $sth1->execute($datasource_id, $forge_id);
    my $filesInDB = $sth1->fetchall_arrayref;
    $sth1->finish();

	foreach my $row (@$filesInDB) 
    {
        my ($ds, $fileLoc) = @$row;
        print "==================\n";
        parseFile($dbh2, $dbh3, $ds, $fileLoc);
    }   	
	
	$dbh1->disconnect(); 
	$dbh2->disconnect();
	$dbh3->disconnect();
}
else
{
	print "You need both a datasource_id and a date to start on your commandline.";
	exit;
}

# --------------------------------------------------
# subroutine: parseFile
# takes: two database connections (local and remote) and a datasource_id
# purpose:
# --get each file on disk
# --pull out the lines
# --parse out the pieces of the lines
# --write each line to the irc table in both local and remote db
# --------------------------------------------------
sub parseFile($dbh2, $dbh3, $ds, $fileLoc)
{
    my $p_dbh2  = $_[0];
    my $p_dbh3  = $_[1];
    my $p_ds    = $_[2];
    my $p_fileLoc = $_[3];

    #date is in the filename, in the format:
    # 48039/20140306
    my $datelog ="";
    if ($p_fileLoc =~ m{^(.*?)\/(.*?)$}s)
    {              
        my $tempdate = $2;
        print "got [$tempdate] for date\n";
        
        if ($tempdate =~ m{^(\d\d\d\d)(\d\d)(\d\d)}s)
        {
        	$datelog = $1 . "-" . $2 . "-" . $3;
        }
    }
    
    # open the file
    print "opening file: $p_fileLoc ($datelog)\n";
    open (FILE, $p_fileLoc) || die "can't open $p_fileLoc: $!\n";
    
    
    my $linenum = 0;
    while(my $line = <FILE>)  
    {      
        print $line;
        $linenum++;
        my $send_user = "";
        my $timelog = "";
        my $line_message = "";
        my $type = "";
        
        # parse out rest of details & insert
        # 1. get system message vs regular message, parse
        # 2. insert
        #
        # here are the two patterns:
        # [20:05] <zmhassan> any tips would be gladly appreciated
        # [16:09] *** jbonofre has quit IRC (Excess Flood)
        
        if ($line =~ m{^\[(.*?)\]\s+\<(.*?)\>\s+(.*?)$}s) #regular message
        {
            $timelog = $1;
            $send_user = $2;
            $line_message = $3;
            $type = "message";
        } 
        
        elsif($line =~ m{^\[(.*?)\]\s+\*\*\*\s+(.*?)$}s) # system message
        {
            $type = "system";
            $timelog = $1;
            $line_message = $2;
        }  
    	
        print "inserting row $linenum for $datelog ($send_user, $timelog, [" . substr($line_message,0,10) . "]\n";
        #======
        # LOCAL
        #======                
        if (($p_ds) && ($type ne ""))
        {
            my $insert2 = $p_dbh2->prepare(qq{
                            INSERT IGNORE INTO apache_activemq_irc
                                (datasource_id, 
                                line_num,
                                full_line_text,
                                line_message,
                                date_of_entry,
                                time_of_entry,
                                type,
                                send_user,
                                last_updated) 
                            VALUES (?,?,?,?,?,?,?,?,NOW())
                            });
            $insert2->execute($p_ds, $linenum, $line, $line_message, $datelog, $timelog, $type, $send_user)
                or die "Couldn't execute statement on LOCAL: " . $insert2->errstr;
            $insert2->finish();
        } 
        #======
        # SYR
        #======
        if (($p_ds) && ($type ne ""))
        {
            my $insert3 = $p_dbh3->prepare(qq{
                            INSERT IGNORE INTO apache_activemq_irc
                                (datasource_id, 
                                line_num,
                                full_line_text,
                                line_message,
                                date_of_entry,
                                time_of_entry,
                                type,
                                send_user,
                                last_updated) 
                            VALUES (?,?,?,?,?,?,?,?,NOW())
                            });
            $insert3->execute($p_ds, $linenum, $line, $line_message, $datelog, $timelog, $type, $send_user)
                or die "Couldn't execute statement on SYR: " . $insert3->errstr;
            $insert3->finish();
        } 
    }
}	
		
