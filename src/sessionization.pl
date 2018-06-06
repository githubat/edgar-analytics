#! /usr/bin/perl

use strict;
use warnings;

use Time::Local qw(timegm_nocheck);
use POSIX qw(strftime);

use Data::Dumper;

#####

# Get our input file filenames

my $infile = $ARGV[0];

# time out value file
my $tofile = $ARGV[1];

my $outfile = $ARGV[2];

chomp($infile);
chomp($outfile);
chomp($tofile);

#####
#
# Global variables
#
#####

my $ses_tmout = 0;

# time stamp from last input entry
my $last_tm = 0;

# time stamp for the current input entry
my $cur_tm = 0;

# difference between $last_tm and $cur_tm
my $tm_delta = 0;

# serial number to keek track of the order of the ip entry bening added
my $sno = 1;

# debugging flag
my $dbg = 0;
my $dbg_dumper = 0;

# fields we are interested what is from the first line of the input file
my @key_field = qw( ip date time cik accession extention );

# ftm   = time stamp when the IP entry is added
# ltm   = time stamp when the IP entry is updated (new document access)
# sno   = serial number
# dcnt  = viewed document counter
# tocnt = timeout counter (space vs time to avoid massive time difference 
#                          calculation each round in invalidate_ip_tab)

my @tab_field = qw( ftm ltm sno dcnt tocnt );

my %key_val = ();
my %key_ndx = ();
my %ip_tab = ();

#####
#
#  Subroutines
# 
#####

# Convert time string to seconds since epoch
# $seconds = &timegm_nocheck($second,$minute,$hour,$day,$month-1,$year-1900);
sub str2time
{
  my @t = split( " ", shift );
  my ( $year, $month, $day, $hh, $mm, $ss ) = (0) x 6;

  ( $year, $month, $day ) = split( "-",$t[0] );
  ( $hh, $mm, $ss ) = split( ":",$t[1] );

  printf( "%s-%s-%s %s:%s:%s", $year, $month, $day, $hh, $mm, $ss ) if $dbg;

  return  &timegm_nocheck( $ss, $mm, $hh, $day, $month - 1, $year - 1900 );

}

#====================================================================================

# Convert seconds sinceepoch value to string
sub time2str
{
  my $tmvar = shift;
  my ( $year, $month, $day, $hh, $mm, $ss ) = (0) x 6;

  return strftime '%Y-%m-%d %H:%M:%S', gmtime $tmvar;
}

#====================================================================================

sub print_key_val
{
  # print out value of each field
  printf "%20s\t", $key_val{ $_ } foreach (@key_field);
  print "\n";
}

#====================================================================================

sub print_ip_entry
{
  my $ip = shift;
  printf "%20s\t", $ip;
  printf "%8s\t", $ip_tab{ $ip }{$_} foreach (@tab_field);
  print "\n";
}

#====================================================================================

sub dump_ip_tab
{
  # Sort on the $ltm and $sno field

  my @sorted_keys = sort { $ip_tab{$a}{ltm} <=> $ip_tab{$b}{ltm} or 
                           $ip_tab{$a}{sno} <=> $ip_tab{$b}{sno}
                         } keys %ip_tab;

  if ( $dbg ) {
    print "\n", "#" x 10, "\n";
    print_ip_entry($_) foreach (@sorted_keys);
    print "#" x 10, "\n\n";
  };
}

#####

# Add an entry to the ip tables
sub add_ip_entry
{
  # 4 keys in the 2nd level hash
  #
  # ftm   = first time
  # ltm   = last time
  # sno   = serial numnber
  # dcnt  = docunent access count
  # tocnt = timeout counter 

  my $ip = $key_val{ip};
  $ip_tab{ $ip }{ftm}   = $cur_tm;
  $ip_tab{ $ip }{ltm}   = $cur_tm;
  $ip_tab{ $ip }{sno}   = $sno++;
  $ip_tab{ $ip }{dcnt}  = 1;
  $ip_tab{ $ip }{tocnt} = 0;
}

#####

sub update_ip_entry
{
  # increase dcnt by 1
  # reset tmcnt to 0

  my $ip = $key_val{ip};

  $ip_tab{ $ip }{ltm} = $cur_tm;
  $ip_tab{ $ip }{dcnt}++;
  $ip_tab{ $ip }{tocnt} = 0;

  # print_ip_entry( $ip );
}

#####

sub add_ip
{
  # check to see if an entry already exists in the has table
  # if yes, update it, if no, add it

  if ( exists $ip_tab{ $key_val{ip} } ) {
    update_ip_entry;
  } else {
    add_ip_entry;
  };
}

#####

sub delete_ip
{
  my $k = shift;

  print "DELETING $k\n" if $dbg;

  print "BEFORE", Dumper( %ip_tab ), "\n" if $dbg_dumper;;
  delete $ip_tab{ $k };
  print "AFTER", Dumper( %ip_tab ), "\n\n" if $dbg_dumper;
}

#####

# Write out to output file

sub write_outfile
{
  my $k = shift;
  my $duration = shift;

  printf OUTFILE "%s,", $k;
  printf OUTFILE "%s,", time2str( $ip_tab{ $k }{ $_ } ) foreach ( qw ( ftm ltm ) );
  printf OUTFILE "%u,", $duration;
  printf OUTFILE "%u",  $ip_tab{ $k }{ dcnt };
  printf OUTFILE "\n";
}

#####

sub output_ip_entry
{
  my $k = shift;
  # We add 1 at the end as it's inclusive 
  write_outfile( $k,  ($ip_tab{ $k }{ ltm } - $ip_tab{ $k }{ ftm } + 1) );
}

#####

# Output timed out session and remove the entry from the ip_tab hash

sub output_and_delete_entry
{
  my ( $key, $tmout, $index );

  my ( @tmp_keys, @sorted_keys ) = ()x2;

  # We first reverse sort by the tocnt
  @sorted_keys = reverse sort { $ip_tab{$a}{tocnt} <=> $ip_tab{$b}{tocnt} } keys %ip_tab;

  if ($dbg) {
    print "##### REVERSE SORT cur_tm = $cur_tm\n\n";
    print "*" x 10, "\n";
    print_ip_entry($_) foreach (@sorted_keys);
    print "*" x 10, "\n\n";
  };

  # initial condition / sanity check
  if ( $#sorted_keys > 0 ) {

    # get all the entries that have expired into @tmp_keys arrary
    # to be sorted by field "sno"

    $index = 0;
    $key = $sorted_keys[ $index++ ];
    $tmout =  $ip_tab{ $key }{ tocnt };

    while ( $tmout == $ses_tmout ) {
      push @tmp_keys, $key;
      $key = $sorted_keys[ $index++ ];
      $tmout =  $ip_tab{ $key }{ tocnt };
    };

    # Now we have all the timeout entries, sort it with the serial number
    @sorted_keys = ();
    @sorted_keys = sort { $ip_tab{$a}{sno} <=> $ip_tab{$b}{sno} } @tmp_keys;

    if ($dbg) {
      print "##### SORTED BY SNO\n";
      print "*" x 10, "\n";
      print_ip_entry($_) foreach (@sorted_keys);
      print "*" x 10, "\n\n";
    };

    foreach $key (@sorted_keys) {
      output_ip_entry( $key );
      delete_ip( $key );
    };
  };
}

#####

sub output_all_entries
{
  my @sorted_keys = ();
  @sorted_keys = sort { $ip_tab{$a}{sno} <=> $ip_tab{$b}{sno} } keys %ip_tab;

  foreach (@sorted_keys) {
    output_ip_entry( $_ );
    delete_ip( $_ );
  }
}

#####

sub read_header_line
{
  my @in_buf = ();

  # First line define the name of each field of the data
  # ip,date,time,zone,cik,accession,extention,code,size,idx,norefer,noagent,find,crawler,browser
  @in_buf = split(/,/,shift);

  # Get the index number for each field so we can refer the field name by the index later
  @key_ndx{ @in_buf } = ( 0..$#in_buf );
}

#####

sub read_one_line
{
  my @in_buf = ();

  # process the input line
  @in_buf = split( /,/,shift);

  $last_tm = $cur_tm;

  # get the value of each key we are interested
  $key_val{ $_ } = @in_buf[ $key_ndx{ $_ } ] foreach (@key_field);

  $cur_tm = str2time( $key_val{date} . " " . $key_val{time} );
  $tm_delta = $cur_tm - $last_tm;


  # Debugging
  dump_ip_tab if $dbg;
}

#####

sub invalidate_ip_tab
{
  # 1. write output and delete ip_tab entry if timeout has reached
  output_and_delete_entry;

  # 2. increase tocnt by tm_delta
  $ip_tab{$_}{tocnt} += $tm_delta foreach (keys %ip_tab);

  dump_ip_tab if $dbg;
}

#####

###########
# main
###########

# Setup for business opening - get our timeout value first
open(IN,$tofile) || die "can't open file $infile for reading\n";
$ses_tmout=<IN>;
close(IN);

# Now we are in business

open(IN,$infile) || die "can't open file $infile for reading\n";
open(OUTFILE,">",$outfile) || die "can't open file $outfile for writing\n";

$_ = <IN> || die "can't read header field definition line from input file $infile\n";
print $_ if $dbg;
chomp;
read_header_line($_);

# Read the first line but do not call the invalidate_ip_tab routine at this time as there is nothing 
# to invalidate at this time. This also allows correct initial condition to be setup for the following looping,
# as we will NOT be adding the (wrong initial condition) $delta_tm to the $tocnt field of the hash entry)

$_ = <IN> || die "can't read fist data line from input file $infile\n";
print $_ if $dbg;
chomp;
read_one_line($_);
# Add the new the ip_tab 
add_ip;

# Now we loop and process each incoming entry
while (<IN>) {

  print $_ if $dbg;
  chomp;
  read_one_line($_);

  # if the time has advancede, check and invalidate (write to output) timeout sessions
  invalidate_ip_tab if ( $tm_delta > 0 );

  # Add the new entry to the ip_tab 
  add_ip;
};

# Clean up 
output_all_entries;

print "##### Last Dump #####" if $dbg;
dump_ip_tab if $dbg;

close(IN);
close(OUTFILE);

exit 0;
