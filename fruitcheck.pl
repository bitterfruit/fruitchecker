#!/usr/bin/perl
# fruitcheck - compare csv files and show report in a gui.

use strict;
use warnings;
use Tk;
use Tk::Adjuster;
use Tk::BrowseEntry;
use Tk::HList;         #The hierarchical list module
require Tk::ItemStyle;
use Tk::LabFrame;      #The frame module

#require Tk::ItemStyle;
#use Tk::ProgressBar;
use FileHandle;
use Cwd 'abs_path';
use lib qw( blib/lib lib );
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
#use File::Find;
#use File::Path;
#use File::Copy;
use Encode; #encode lang
# use utf8;
use MIME::Base64;


# Global Variables

my $version = "0.05 ()";
my $VerboseLevel = 0;  # show verbose output, 0=none, 3=shitload
foreach (@ARGV) {
  $VerboseLevel = $1 if /^(?:--verbose=|-v)(\d+)/ && $1<4;
  if (not /^--verbose=\d|^-v\d+/) {
    print "Error: Unknown parameter! Accepted parameter:\n";
    print " --verbose=# or -v# , where # is one of 0..3\n"; exit 1;
  }
}
my $cygwin_basepath = qx/cygpath -w \// if isCygwin();
chomp($cygwin_basepath)                 if isCygwin();
my %griditems; # associate grit item with details about the match for each row in the grid
my $CSVFILE1="";
my $CSVFILE2="";
my $file1count=0;
my $file2count=0;
my %opt;
$opt{'hideidentical'} = 0;
$opt{'ignoredescriptions'} = 0;
$opt{'ignorepathnames'} = 0;
$opt{'tkbrowser'} = 0;
#$opt{'saveascsvchoices'} = 0;
my %stats;
$stats{'onlyin1'} = 0;
$stats{'onlyin2'} = 0;
$stats{'identical'} = 0;
$stats{'dupesin1'} = 0;
$stats{'dupesin2'} = 0;
$stats{'different'} = 0;
my $rdb_saveascsv = 0; # Radiobutton group variable


# Main Window

if ( isCygwin() && ! -f "/tmp/.X0-lock" ) {
  # start XWin Server
  print "startxwin\n";
  system("run.exe /usr/bin/bash.exe -l -c /usr/bin/startxwin.exe&");
  while( -f "/tmp/.X0-lock" ) { sleep(1); }
  sleep(1);
}
my $mw = new MainWindow( title => "FruitCheck $version" );
#$mw->resizable(0,0); # no-resizeable
$mw->optionAdd('*font', 'Helvetica 9');

my $files_frame   = $mw -> Frame();
my $file1_label1  = $files_frame -> Label( -text=>"CSV file 1:" );
my $file1_path    = $files_frame -> Button(
  -width   => 80,
  -height  => 1,
  -relief  => "sunken",
  -command => sub{ browse_callback("file1"); },
  -text    => ""
);
my $file1_entries = $files_frame -> Label( -text => "0"          );
my $file1_label2  = $files_frame -> Label( -text => "entries"    );
my $file2_label1  = $files_frame -> Label( -text => "CSV file 2:");
my $file2_path    = $files_frame -> Button(
  -width   => 80,
  -height  => 1,
  -relief  => "sunken",
  -command => sub{ browse_callback("file2"); },
  -text    => ""
);
my $file2_entries = $files_frame -> Label( -text=>"0"       );
my $file2_label2  = $files_frame -> Label( -text=>"entries" );

# the HList: http://usadev.wordpress.com/2010/04/25/creating-gui-in-tk/
my $lframe = $mw->LabFrame(
  -label  => "Report", #A frame title
  -height => 130,   #Frame height
  #-width   => 353,   #Frame width
);
my @headers_report = ( "Filename", "Compare Results"); #Columns headers
my $grid = $lframe->Scrolled(
  'HList',
  -head       => 1,  #Enabling columns headers
  -columns    => scalar @headers_report, #Number of columns
  -scrollbars => "oe",
  -width      => 80,
  #-height     => 20,
  -padx       => 4,
  -background => 'white',     #Background color
  -browsecmd  => \&grid_browsecmd,
)->pack(-side=>'top', -fill=>'both', -expand=>1);

my $optframe = $mw->LabFrame(
  -label  => "Options", #A frame title
  #-height => 130,       #Frame height
  #-width => 353,      #Frame width
);
my $chb_hideiden = $optframe -> Checkbutton(
  -text     => "Hide Identical",
  -state    => "normal",
  -variable => \$opt{'hideidentical'},
  -command  => \&command_hideidentical
);
my $chb_igndesc  = $optframe -> Checkbutton(
  -text     => "Ignore Descriptions",
  -state    => "disabled",
  -variable => \$opt{'ignoredescriptions'},
  -command  => sub { compare_csvs($CSVFILE1,$CSVFILE2); }
);
my $chb_ignpath  = $optframe -> Checkbutton(
  -text     => "Ignore Pathnames",
  -state    => "disabled",
  -variable => \$opt{'ignorepathnames'},
  -command  => sub { compare_csvs($CSVFILE1,$CSVFILE2); }
);
my $lbl_onlyin1     = $optframe -> Label( -text => "0" );
my $lbl_onlyin2     = $optframe -> Label( -text => "0" );
my $lbl_identical   = $optframe -> Label( -text => "0" );
my $lbl_duplicates1 = $optframe -> Label( -text => "0" );
my $lbl_duplicates2 = $optframe -> Label( -text => "0" );
my $lbl_different   = $optframe -> Label( -text => "0" );

my @headers_details = ( "", "Filename", "Size", "Crc32", "Path", "Description"  );
my $detailsframe = $mw->LabFrame(
  -label  => "Details",
#  -height => 10,
#  -width  => 0,
);
my $grid2 = $detailsframe->HList(
  -head       => 1,
  -columns    => scalar @headers_details,
  -width      => 4,
  -height     => 5,
  -padx       => 4,
  -background => 'white',
)->pack(-side=>'top', -fill=>'both', -expand=>1);

my $style_identical = $mw->ItemStyle(
  'text',
  -foreground       => 'black',
  -selectforeground => 'black',
  -background       => 'white',
  -selectbackground => 'white',
#  -font=>'TkFixedFont 8 bold'
);
my $style_different = $mw->ItemStyle(
  'text',
  -foreground       => 'red',
  -selectforeground => 'red',
  -background       => 'white',
  -selectbackground => 'white',
);
my $style_duplicate = $mw->ItemStyle(
  'text',
  -foreground       => 'orange',
  -selectforeground => 'orange',
  -background       => 'white',
  -selectbackground => 'white',
);
my $style_onlyin = $mw->ItemStyle(
  'text',
  -foreground       => 'blue',
  -selectforeground => 'blue',
  -background       => 'white',
  -selectbackground => 'white',
);


# Geometry Management

$file1_label1    -> grid( -row=>1, -column=>1, -sticky=>"e"  );
$file1_path      -> grid( -row=>1, -column=>2, -sticky=>"we"  );
$file1_entries   -> grid( -row=>1, -column=>3, -sticky=>"we" );
$file1_label2    -> grid( -row=>1, -column=>4, -sticky=>"w"  );
$file2_label1    -> grid( -row=>2, -column=>1, -sticky=>"e"  );
$file2_path      -> grid( -row=>2, -column=>2, -sticky=>"we"  );
$file2_entries   -> grid( -row=>2, -column=>3, -sticky=>"we" );
$file2_label2    -> grid( -row=>2, -column=>4, -sticky=>"w"  );
$chb_hideiden    -> grid( -row=>1, -column=>1, -sticky=>"nw" );
$chb_igndesc     -> grid( -row=>2, -column=>1, -sticky=>"nw" );
$chb_ignpath     -> grid( -row=>3, -column=>1, -sticky=>"nw" );
$lbl_onlyin1     -> grid( -row=>4, -column=>1, -sticky=>"nw" );
$lbl_onlyin2     -> grid( -row=>5, -column=>1, -sticky=>"nw" );
$lbl_identical   -> grid( -row=>6, -column=>1, -sticky=>"nw" );
$lbl_duplicates1 -> grid( -row=>7, -column=>1, -sticky=>"nw" );
$lbl_duplicates2 -> grid( -row=>8, -column=>1, -sticky=>"nw" );
$lbl_different   -> grid( -row=>9, -column=>1, -sticky=>"nw" );

$files_frame     -> pack(-side=>'top', -fill=>'x', -expand=>0);
$detailsframe    -> pack(-side=>'bottom', -fill=>'x', -expand=>0);
$lframe          -> pack(-side=>'left', -fill=>'both', -expand=>1);
$optframe        -> pack(-side=>'left', -fill=>'both', -expand=>1);
#$files_frame     -> grid( -row=>1, -column=>1, -sticky=>"nsew", -columnspan=>2);
#$lframe          -> grid( -row=>2, -column=>1, -sticky=>"nw"   );
#$optframe        -> grid( -row=>2, -column=>2, -sticky=>"nwes" );
#$detailsframe    -> grid( -row=>3, -column=>1, -sticky=>"we", -columnspan=>2);

for(0..scalar @headers_report - 1) {
  $grid->header(
    'create',
    $_,
    -text             => $headers_report[$_],
    -headerbackground => 'gray'
  );
}
for(0..scalar @headers_details - 1) {
  $grid2->header(
    'create',
    $_,
    -text             => $headers_details[$_],
    -headerbackground => 'gray'
  );
}
$grid2->delete('all');


# Menu

my $menubar = $mw -> Menu( -tearoff=>1, -relief => "flat" );
$mw -> configure( -menu => $menubar );
my $mbcinfo = $menubar -> cascade(
  -label     => "File",
  -underline => 0,
  -tearoff   => 0
);
$mbcinfo -> checkbutton(
  -label     => "Use Tk's file browser",
  -variable  => \$opt{'tkbrowser'}
);
$mbcinfo -> command(
  -label     => "Create PICCHECK-CSV",
  -underline => 1,
  -command   => \&command_createcsv
);
$mbcinfo -> command (
  -label     => "Update FruitCheck!",
  -underline => 0,
  -command   => \&command_updatefruitcheck
);
$mbcinfo -> command(
  -label     =>"Exit",
  -underline => 1,
  -command   => sub { exit }
);


# Init


MainLoop;


# Functions

sub command_hideidentical {
  if ($opt{'hideidentical'}==0) {
    $chb_igndesc -> configure(-state=>"disabled");
    $chb_ignpath -> configure(-state=>"disabled");
    $opt{'ignoredescriptions'} = 0;
    $opt{'ignorepathnames'} = 0;
  }
  else {
    $chb_igndesc -> configure(-state=>"normal");
    $chb_ignpath -> configure(-state=>"normal");
  }
  compare_csvs($CSVFILE1,$CSVFILE2);
}

sub grid_browsecmd {
  my $id = shift;
  return if !defined($grid);
  $grid2->delete('all');
  $grid2->add(0);
  $grid2->add(1);
  $grid2->itemCreate(0, 0, -text => "CSV 1:" );
  $grid2->itemCreate(1, 0, -text => "CSV 2:" );
  for my $idx (0..1) { # for csv1 and csv2
    if (defined( $griditems{$id}->[$idx])) {
      $grid2->itemCreate($idx, 1, -text => $griditems{$id}->[$idx]->{'file'} );
      $grid2->itemCreate($idx, 2, -text => $griditems{$id}->[$idx]->{'size'} );
      $grid2->itemCreate($idx, 3, -text => $griditems{$id}->[$idx]->{'crc32'} );
      $grid2->itemCreate($idx, 4, -text => $griditems{$id}->[$idx]->{'path'} );
      $grid2->itemCreate($idx, 5, -text => $griditems{$id}->[$idx]->{'comment'} );
    }
  }
}

sub command_updatefruitcheck {
  my $raw = http_get("https://raw.github.com/bitterfruit/fruitchecker/master/VERSION");

  if ($raw eq "") {
    $mw -> messageBox(
      -type    => "ok",
      -message => "Unable to update FruitCheck.\n"
    );
    return;
  }
  my ($onlver,$onlmd5,$url) = split ",", $raw;
  if ($onlver eq $version) {
    $mw -> messageBox(-type=>"ok",
    -message=>"FruitCheck is at latest version $version.\n");
    return;
  }
  my $newfile = http_get($url);
  if ($newfile eq "") {
    $mw -> messageBox(-type=>"ok",
    -message=>"Unable to update FruitCheck.\n");
    return;
  }
  my $path = "/usr/bin";
  $path = "/usr/local/bin" if -d "/usr/local/bin";
  print "writing ". $path."/fruitcheck_new"."\n";
  open(FILE,">","/tmp/fruitcheck_new") or die $!;
  binmode(FILE);
  print FILE $newfile;
  close(FILE);
  system("chmod 755 /tmp/fruitcheck_new");
  open(PS, "md5sum /tmp/fruitcheck_new 2>&1 |") || die "Failed $!\n";
  my $md5local = "";
  while(<PS>) {
    $md5local = $1 if /([a-f0-9]+)/;
  }
  close(PS);
  print "$md5local $onlmd5\n";
  if ($md5local eq $onlmd5) {
    my $sudo = "";
    if (!isCygwin()) {
      system( "gksu 'rm -v ".$path."/fruitcheck'" ) if -f $path."/fruitcheck";
      system( "gksu 'rm -v /usr/bin/fruitcheck'" ) if -f "/usr/bin/fruitcheck";
      system( "gksu 'mv -v /tmp/fruitcheck_new ".$path."/fruitcheck'");
    }
    else {
      system( "rm -v ".$path."/fruitcheck" ) if -f $path."/fruitcheck";
      system( "rm -v /usr/bin/fruitcheck" ) if -f "/usr/bin/fruitcheck";
      system( "mv -v /tmp/fruitcheck_new ".$path."/fruitcheck");
    }
    #chmod(755, $path."/fruitcheck");
    $mw -> messageBox(-type=>"ok",
        -message=>"FruitCheck updated. Press OK to restart FruitCheck.");
    system("fruitcheck&"); exit;
  }
  else {
    $mw -> messageBox(-type=>"ok",
    -message=>"MD5 sums doesn't match. Update fail!");
      system( "rm -v /tmp/fruitcheck_new" );
  }
  return;
}

sub browse_callback {
  printdeb(1, "fruitcheck::browse_src()\n");
  my $file12 = shift; # "file1" or "file2".
  my $path;
  $path = $CSVFILE1 if ($file12 eq "file1");
  $path = $CSVFILE2 if ($file12 eq "file2");
  $path = $CSVFILE1 if $path eq "" && ($file12 eq "file2");
  $path = $CSVFILE2 if $path eq "" && ($file12 eq "file1");
  my ($startdir) = ($path =~ /^(.*\/).*?$/);
  $startdir = "" if !defined($startdir);
  print $path."\n\n";
  
  my $hasWin32GUI = 0; # has Win32::GUI test
  if (!isCygwin() && $opt{'tkbrowser'}==0 && (-f "/usr/bin/zenity") ) {
    open(PS, "/usr/bin/zenity --file-selection --filename='$startdir' --file-filter='CSV files (*.csv) | *.csv' --file-filter='All files (*) | *' --title=\"Select a Source Directory\" --window-icon=/usr/share/pixmaps/ZIP-File-icon_48.png |") || die "Failed $!\n";
    $path=<PS>;
    chomp $path;
  }
  else {
    if ( $opt{'tkbrowser'}==0 ) {
      #http://stackoverflow.com/questions/251694/how-can-i-check-if-i-have-a-perl-module-before-using-it
      eval {
        require Win32::GUI;
        $startdir = win_path($startdir) if $path ne "";
        print $startdir."\n";  print $path."\n\n";
        $path = Win32::GUI::BrowseForFolder( -root => 0x0000 , -editbox => 1,
                                           -directory => $startdir, -title => "Select a Source Directory",
                                           -includefiles=>1, -addexstyle =>"WS_EX_TOPMOST");
      };
      unless($@)
      {
        $path = cyg_path($path);
        printdeb(1, "Gui Loaded successfully $path\n");
        if ( $path ne "" ) { # use ne for string, and != for numerics
          $path  = encode("windows-1252", $path);
        }
        $hasWin32GUI=1;
      }
    }
    my @types = (["CSV files", [qw/.csv/]], ["All files", '*'] );
    $path = $mw->getOpenFile(-initialdir=>$startdir, -filetypes => \@types) if !$hasWin32GUI;
  }
  $path  = encode("windows-1252", $path);
  return if not isCSVfile($path);
  if ( $path ne "" ) {
    my ($dir,$file) = ($path =~/^(.*)\/(.*?)$/);
    if ($file12 eq "file1") {
      if ($path ne $CSVFILE2) {
        $CSVFILE1 = $path;
        $file1_path->configure(-text=>$file);
        $file1_path->configure(-foreground=>'black');
        $file1_path->configure(-activeforeground=>'black');
      }
      else {
        # put red color on button text if user tries to select two of same file
        $file1_path->configure(-foreground=>'red');
        $file1_path->configure(-activeforeground=>'red');
      }

    }
    else {
      if ($path ne $CSVFILE1) {
        $CSVFILE2 = $path;
        $file2_path->configure(-text=>$file);
        $file2_path->configure(-foreground=>'black');
        $file2_path->configure(-activeforeground=>'black');
      }
      else {
        $file2_path->configure(-foreground=>'red');
        $file2_path->configure(-activeforeground=>'red');
      }
    }
  }
  my $csvfile;
  $csvfile = $CSVFILE1 if $file12 eq "file1";
  $csvfile = $CSVFILE2 if $file12 eq "file2";
  return if !isCSVfile($csvfile);
  count_entries($file12,$csvfile);
  compare_csvs( $CSVFILE1, $CSVFILE2);
  return;  
}

sub command_createcsv {
  printdeb(1, "fruitcheck::command_createcsv()\n");
  my $mwtl = $mw->Toplevel(
    -title  => "Create a PICCHECK compatible CSV",
    -height => 10,
    -width  => 100,
    -bd     => 5
  );
  my $mwtl_topframe = $mwtl->Frame();
  my $lbl_dir  = $mwtl_topframe -> Label (
    -text   => "Directory:"
  )->pack( -side => 'left', -fill=>'x', -expand=>0);
  my $btn_path = $mwtl_topframe -> Button(
    -text    => "",
    -width   => 80,
    -height  => 1,
    -relief  => "sunken", # raised, sunken, flat, ridge, solid, or groove
  )->pack( -side => 'left', -fill=>'x', -expand=>1 );
  my $btn_create = $mwtl_topframe -> Button (
    -text => "Create",
  )->pack( -side => 'left',-fill=>'x', -expand=>0 );
  $mwtl_topframe->pack(-side => 'top', -fill=>'x', -expand=>1);
  my $mwtl_frame = $mwtl -> Frame () -> pack (-side=>'bottom', -fill=>'both', -expand=>1);
  my $lbl_status = $mwtl_frame -> Label (
    -text => "",
	-width => 80
  )->pack( -side => 'bottom' );
  $btn_create -> configure(
    -command => sub {
      my $path = $btn_path->cget(-text);
      if ( $path ne "" && -d $path) {
        printdeb(1,"Do something to $path \n");
        $btn_create -> configure( -state=>"disabled" );
        $mwtl -> update();
        my $basepath = $path;
        $basepath =~ s/\/$//;
        my %filehash;
        list_files_recursive($path,\%filehash);
		my ($i, $n) = (0, scalar(keys %filehash));
		my ($basefoldername) = ($basepath =~ /.*\/(.*?)$/);
        printdeb(2,"filehash size: $n and basefoldername: $basefoldername\n");
		open(FILE, ">", "$basepath/$basefoldername.csv") or die "$!";
        foreach my $filepath ( sort keys %filehash ) {
		  printdeb(3,"foreach_filepath $i/$n $filepath\n");
		  $lbl_status->configure(-text=>"$i/$n");
		  $mwtl->update();
          my $fh = FileHandle->new();
          if ( !$fh->open( $filepath, 'r' ) ) {
              warn "$0: $!\n";
              next;
          }
          binmode($fh);
          my $buffer;
          my $bytesRead;
          my $crc = 0;
          while ( $bytesRead = $fh->read( $buffer, 32768 ) ) {
              $crc = Archive::Zip::computeCRC32( $buffer, $crc );
          }
          $crc = uc(sprintf( "%08x", $crc ));
          my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
              $atime,$mtime,$ctime,$blksize,$blocks) = stat($filepath);
          $filepath =~ s/\//\\/g;
          my $relative_path = substr $filepath, length($basepath)+1;
          my ($relative_dir, $file) =  ($relative_path =~ /^(.*\\)?(.*)?$/);
          $relative_dir = "" unless defined($relative_dir);
          print      "$file,$size,$crc,\\$relative_dir,\n";
          print FILE "$file,$size,$crc,\\$relative_dir,\n";
          $i++;
        }
        close(FILE);
        $btn_create -> configure( -state=>"active");
        $lbl_status->configure(-text=>"");
		$mwtl->update();
      }
    }
  );
  $btn_path -> configure ( # late configuration of this button.
    -command => sub{ 
      my $path = browseforfolder( $btn_path->cget(-text) );
      $btn_path->configure(-text=>$path) unless $path eq "";
      print "Path $path\n";
    },
  );
}


sub browseforfolder {
  my $startdir = shift;
  printdeb(1,"fruitcheck::fileselector_window($startdir)\n");
  my $path = "";
  my $hasWin32GUI = 0; # has Win32::GUI test
  if (!isCygwin() && $opt{'tkbrowser'}==0 && (-f "/usr/bin/zenity") ) {
    open(PS, "/usr/bin/zenity --file-selection --directory --filename='$startdir' --title=\"Select a Directory\" --window-icon=/usr/share/pixmaps/ZIP-File-icon_48.png |") || die "Failed $!\n";
    $path=<PS>;
    chomp $path;
    return $path;
  }
  else {
    if ( $opt{'tkbrowser'}==0 ) {
      #http://stackoverflow.com/questions/251694/how-can-i-check-if-i-have-a-perl-module-before-using-it
      eval {
        require Win32::GUI;
        $startdir = win_path($startdir) unless $startdir eq "";
        print "win32 gui startdir: $startdir\n";  print $path."\n\n";
        $path = Win32::GUI::BrowseForFolder( -root => 0x0000 , -editbox => 1,
                                           -directory => $startdir, -title => "Select a Directory",
                                           -includefiles=>0, -addexstyle =>"WS_EX_TOPMOST");
      };
      unless($@)
      {
        $path = cyg_path($path);
        printdeb(1, "Win32-Gui Loaded successfully $path\n");
        if ( $path ne "" ) {
          $path  = encode("windows-1252", $path);
        }
        #$hasWin32GUI=1;
        return $path;
      }
    }
    my @types = (["CSV files", [qw/.csv/]], ["All files", '*'] );
    $path = $mw->chooseDirectory(
      -initialdir=>$startdir, 
      -title=>"Select a Directory"
    ) if !$hasWin32GUI;
    return $path;
  }
}

sub count_entries {
  my $file12 = shift;
  my $csvfile = shift;
  return if !isCSVfile($csvfile);
  my $count=0;
  open(FILE,"<",$csvfile) or die "$!";
  while(<FILE>) {
    $count++;
  }
  close(FILE);
  $file1_entries->configure(-text=>"$count") if $file12 eq "file1";
  $file2_entries->configure(-text=>"$count") if $file12 eq "file2";
}

sub compare_csvs {
  my %csvindex;
  my @csvfiles = @_;
  printdeb(1,"fruitcheck::compare_csvs($csvfiles[0],$csvfiles[1])\n");
  return if (isCSVfile($csvfiles[0])==0 or isCSVfile($csvfiles[1])==0);
  $grid->delete('all');
  $grid2->delete('all');
  print $csvfiles[0]."\n";
  print $csvfiles[1]."\n";
  my $count=0;
  for my $filenum (0..1) {
    open(FILE,"<",$csvfiles[$filenum]) or die "$!";
    while(<FILE>) {
      $count++;
      my ($file,$fsize,$crc32,$path,$comment) = split(",");
      push @{$csvindex{"$crc32$fsize"}}, { 'csvfile'=>$filenum+1, 'file'=>$file, 'size'=>$fsize, 'crc32'=>$crc32, 'path'=>$path, 'comment'=>$comment };
    }
    close(FILE);
  }
  
  my $lnum = 0;
  foreach my $key (sort { $csvindex{$a}->[0]->{'file'} cmp $csvindex{$b}->[0]->{'file'} } keys %csvindex) {
    printdeb(3,"compare_csvs - key $key\n");
    if (scalar(@{$csvindex{$key}})==1) {
       $grid->add($lnum);
       $grid->itemCreate($lnum, 0, -text => $csvindex{$key}->[0]->{'file'}, style=>$style_onlyin );
       $grid->itemCreate($lnum, 1, -text => "only in csv".$csvindex{$key}->[0]->{'csvfile'}, style=>$style_onlyin  );
       $griditems{$lnum} = [$csvindex{$key}->[0] , undef ] if $csvindex{$key}->[0]->{'csvfile'}==1;
       $griditems{$lnum} = [ undef, $csvindex{$key}->[0] ] if $csvindex{$key}->[0]->{'csvfile'}==2;
       $stats{'onlyin1'}++ if $csvindex{$key}->[0]->{'csvfile'}==1;
       $stats{'onlyin2'}++ if $csvindex{$key}->[0]->{'csvfile'}==2;
       $lnum++;
       print $csvindex{$key}->[0]->{'file'}."\t";
       print "only in csv".$csvindex{$key}->[0]->{'csvfile'}."\n";
    }
    elsif (scalar(@{$csvindex{$key}})==2) {
      compare_two($csvindex{$key}->[0], $csvindex{$key}->[1], \$lnum );
    }
    elsif (scalar(@{$csvindex{$key}})>2) {
      print "OMG, you three entries equal ? ??!\n";
      my $nfiles = scalar(@{$csvindex{$key}});
      for my $i (0..$nfiles-1) {
        for my $j ($i+1..$nfiles-1) {
          #print "$nfiles $i $j\n";
          compare_two($csvindex{$key}->[$i],$csvindex{$key}->[$j], \$lnum);
        }
      }
    }
  }
  print $count."\n";
  update_stats();
}

sub compare_two {
  my $file1 = shift;
  my $file2 = shift;
  my $lnum_ref = shift;
  printdeb(1,"fruitcheck::compare_two(".$file1->{'file'}.",".$file2->{'file'}.",$$lnum_ref)\n");
  if ( $file1->{'file'} eq $file2->{'file'} ) { # same filename
    if ($file1->{'csvfile'} eq $file2->{'csvfile'}) {
      print $file1->{'file'}. "\tduplicate in csv".$file1->{'csvfile'}."\n";
      $grid->add($$lnum_ref);
      $grid->itemCreate($$lnum_ref, 0, -text => $file1->{'file'}, style=>$style_duplicate);
      $grid->itemCreate($$lnum_ref, 1, -text => "duplicate in csv".$file1->{'csvfile'}, style=>$style_duplicate );
      $griditems{$$lnum_ref} = [ $file1, undef] if $file1->{'csvfile'}==1;
      $griditems{$$lnum_ref} = [ undef, $file1] if $file1->{'csvfile'}==2;
      $stats{'dupesin1'}++ if $file1->{'csvfile'}==1;
      $stats{'dupesin2'}++ if $file1->{'csvfile'}==2;
      $$lnum_ref++;
    } else {
      if ( $file1->{'path'} eq $file2->{'path'} ) {
        if ($opt{'hideidentical'}==0) {
          print $file1->{'file'}. "\tidentical\n";
          $grid->add($$lnum_ref);
          $grid->itemCreate($$lnum_ref, 0, -text => $file1->{'file'}, style=>$style_identical);
          $grid->itemCreate($$lnum_ref, 1, -text => "identical", style=>$style_identical );
          $griditems{$$lnum_ref} = [ $file1, $file2];
          $$lnum_ref++;
        }
        $stats{'identical'}++;
      } else {
        if ($opt{'ignorepathnames'}==0) {
          print $file1->{'file'}. "\tdifferent path\n";
          $grid->add($$lnum_ref);
          $grid->itemCreate($$lnum_ref, 0, -text => $file1->{'file'}, style=>$style_different );
          $grid->itemCreate($$lnum_ref, 1, -text => "different path", style=>$style_different );
          $griditems{$$lnum_ref} = [ $file1, $file2];
          $$lnum_ref++;
        }
       $stats{'different'}++;
      }
    } 
  }
  else { # not same filename
    if ($file1->{'csvfile'} eq $file2->{'csvfile'}) { # same csv
      printf ("%s\tduplicate in csv%s\n", $file1->{'file'}, $file1->{'csvfile'} );
      $grid->add($$lnum_ref);
      $grid->itemCreate($$lnum_ref, 0, -text => $file1->{'file'}, style=>$style_duplicate );
      $grid->itemCreate($$lnum_ref, 1, -text => "duplicate in csv".$file1->{'csvfile'}, style=>$style_duplicate );
      $$lnum_ref++;
      $griditems{$$lnum_ref} = [ $file1, undef] if $file1->{'csvfile'}==1;
      $griditems{$$lnum_ref} = [ undef, $file1] if $file1->{'csvfile'}==2;
      $stats{'dupesin1'}++ if $file1->{'csvfile'}==1;
      $stats{'dupesin2'}++ if $file1->{'csvfile'}==2;
    } else { # different csv
      printf ("%s\tdifferentFilename %s\n", $file1->{'file'}, $file2->{'file'} );
      $grid->add($$lnum_ref);
      $grid->itemCreate($$lnum_ref, 0, -text => $file1->{'file'}, style=>$style_different );
      $grid->itemCreate($$lnum_ref, 1, -text => "different filename ".$file2->{'file'}, style=>$style_different );
      $griditems{$$lnum_ref} = [ $file1, $file2];
      $$lnum_ref++;
      $stats{'different'}++;
    }
  }
}

sub update_stats {
  printdeb(1,"fruitcheck::update_stats()\n");
  $lbl_onlyin1     -> configure( -text=> "$stats{'onlyin1'  } entries only in csv1" );
  $lbl_onlyin2     -> configure( -text=> "$stats{'onlyin2'  } entries only in csv2" );
  $lbl_identical   -> configure( -text=> "$stats{'identical'} entries are identical" );
  $lbl_duplicates1 -> configure( -text=> "$stats{'dupesin1'   } duplicates in csv1" );
  $lbl_duplicates2 -> configure( -text=> "$stats{'dupesin2'   } duplicates in csv2" );
  $lbl_different   -> configure( -text=> "$stats{'different'} entries are different" );
  $stats{'onlyin1'  } = 0;
  $stats{'onlyin2'  } = 0;
  $stats{'identical'} = 0;
  $stats{'dupesin1'   } = 0;
  $stats{'dupesin2'   } = 0;
  $stats{'different'} = 0;
}

sub isCSVfile {
  my $file = shift || "";
  printdeb(1,"fruitcheck::isCSVfile($file) -> ");
  my $returnvalue=0;
  $returnvalue =  1 if ($file =~ /.csv$/i && -f $file);
  printdeb(1,$returnvalue."\n");
  return $returnvalue;
}
sub http_get {
  my $url = shift;
  printdeb(1,"fruitcheck::http_get($url)\n");
  eval {
    require LWP::UserAgent;
    require LWP::Protocol::https;
    my $ua2 = LWP::UserAgent->new(timeout => 60, agent => 'fruitcheck $version');
  
  };
  unless($@)
  {
    # required module loaded
    printdeb(2,"fruitcheck::http_get() - using LWP\n");
    my $verifyhost = $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}; # remember it
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    my $ua2 = LWP::UserAgent->new(timeout => 60, agent => 'fruitcheck $version');
    my $res;
    MAIN: for my $retries (0..2) {
      printf('Fetching %s..', $url);
      $res = $ua2->get($url);
      if ($res->is_success) {
         printf("OK (%.2f KiB)\n", length($res->content) / 1024);
         $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = $verifyhost;
         return $res->content;
      } else {
         printf("FAILED (%s)!\n", $res->status_line);
      }
      last if $res->status_line =~ /^(400|401|403|404|405|406|407|410)/;
      sleep(2) if $retries<4;
    }
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = $verifyhost;
    return "";
  }
  else {
    # required module NOT loaded
    if (-f "/usr/bin/wget") {
      printdeb(2,"fruitcheck::http_get() - using wget\n");
      my $html = "";
      print "You have wget\n";
      system("wget --no-check-certificate -O \"/tmp/fruitcheck_http_get\" $url");
      open(TMPFILE,"<","/tmp/fruitcheck_http_get") || die "$!";
      while (<TMPFILE>) { chomp; $html=$html.$_."\n"; }
      close(TMPFILE);
      system("rm /tmp/fruitcheck_http_get");
      return $html;
    }
    elsif (-f "/usr/bin/curl") {
      printdeb(2,"fruitcheck::http_get() - using curl\n");
      my $html = "";
      print "You have curl\n";
      open(PS, "curl $url |");
      while (<PS>) { chomp; $html=$html.$_."\n"; }
      close(PS);
      return $html;
    }
    else {
      print "No tools no means no html. sorry.\n";
      print "You have three options to enable fruitcheck's http capabilities:\n".
            "1. Install the libwww-perl package,\n".
            "2. Install the wget package, or\n".
            "3. Install the curl package.\n";
      return "";
    }
  }
}

sub list_files_recursive {
  my ($path, $filehash, $maxdepth, $level) = @_;
  $path =~ s/([^\/])$/$1\//;
  my $nkeys = keys %{$filehash};
  $maxdepth = 99 if !defined($maxdepth);
  $level = 0 if !defined($level);
  if ($level>0) {
    printdeb (3, "fr..::list_files_recursive() $level $nkeys -> $path\n");
  }
  else {
    printdeb (2, "fr..::list_files_recursive() $level $nkeys -> $path\n");
  }
  return if $level >= $maxdepth;
  return if $nkeys > 1000;
  my @dirs =();
  opendir(DIR, $path) or print "Error: $!\n";
  while (defined(my $dir = readdir(DIR))) {
    next if $dir =~ /^\.$|^\.\.$/ig;
    if ( -d $path.$dir) {
      push @dirs, $dir;
    }
    elsif (-f $path.$dir ) {
        $filehash->{"$path"."$dir"}='';
    }
  }
  closedir(DIR);
  foreach my $dir (@dirs) {
    list_files_recursive($path.$dir."/", $filehash, $maxdepth, $level+1);
  }
}

sub cyg_path {
  my $path = shift || "";
  printdeb(2, "fruitcheck::cyg_path('$path') -> ");
  $path =~ s/^(\w):\\/\/cygdrive\/\L$1\//;
  $path =~ s/\\/\//g;
  printdeb(2, "$path\n");
  return $path;
}

sub win_path {
  printdeb(2, "fruitcheck::win_path()\n" );
  my ( $path ) = @_;
  if (not $path =~ /cygdrive\/\w/) { 
    $path = $cygwin_basepath . $path;
  };
  $path =~ s/^\/cygdrive\/(\w)$/$1\:\\/;
  $path =~ s/^\/cygdrive\/(\w)\/(.*)/$1\:\\$2/;
  $path =~ s/\//\\/g;
  #$path =~ s/\(/\\\(/g;
  #$path =~ s/\)/\\\)/g;
  #$path =~ s/\'/\\\'\\\'/g;
  return $path;
}

sub isCygwin {
  my $cygwin=0;
  if (defined ($ENV{TERM})) {
    $cygwin = 1 if $ENV{TERM} eq "cygwin";
  }
  if (!$cygwin && exists($ENV{WINDIR})) {
    $cygwin = 1 if $ENV{WINDIR} =~ /WINDOWS/i;
  }
  printdeb(2, sprintf ("fruitcheck::isCygwin() - returns %d\n", $cygwin) );
  return $cygwin;
}

sub printdeb {
  my ($level,$message) = @_;
  print $message if $level <= $VerboseLevel;
}

sub check_dir {
  my ($dir) = @_;
  mkpath($dir, 0, 0755) if (! -d $dir);
}
