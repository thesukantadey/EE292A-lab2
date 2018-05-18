=pod

=head1 NAME

acl::Command - Utility commands for the Intel(R) FPGA SDK for OpenCL(TM)

=head1 COPYRIGHT

# (C) 1992-2016 Intel Corporation.                            
# Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
# and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
# and/or other countries. Other marks and brands may be claimed as the property  
# of others. See Trademarks on intel.com for full list of Intel trademarks or    
# the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
# Your use of Intel Corporation's design tools, logic functions and other        
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Intel MegaCore Function License Agreement, or other applicable      
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Intel and sold by    
# Intel or its authorized distributors.  Please refer to the applicable          
# agreement for further details.                                                 
    


=cut

package acl::Command;
require Exporter;
@acl::Command::ISA        = qw(Exporter);
@acl::Command::EXPORT     = ();
@acl::Command::EXPORT_OK  = qw();
use strict;
use acl::Env;
use acl::Board_env;
use acl::Pkg;
our $AUTOLOAD;

my @_valid_cmd_list = qw(
   version
   help
   do
   compile-config
   cflags
   link-config
   linkflags
   ldflags
   ldlibs
   board-path
   board-hw-path
   board-mmdlib
   board-libs
   board-link-flags
   board-default
   board-version
   board-name
   board-xml-test
   reprogram
   program
   flash
   diagnostic
   diagnose
   setup-acd
   install
   uninstall
   example-makefile
   makefile
   binedit
   hash
   report
   vis
   library
   analyze-area
   env
);

my @_valid_list = @_valid_cmd_list, qw( pre_args args cmd prog );

my %_valid_cmd = map { ($_ , 1) } @_valid_cmd_list;

my %_valid = map { ($_ , 1) } @_valid_list;

my @device_map = ();

sub new {
   my ($proto,$prog,@args) = @_;
   my $class = ref $proto || $proto;

   my @pre_args = ();
   my @post_args = ();
   my $subcommand = undef;
   my $first_arg = undef;
   while ( $#args >=0 ) {
      my $arg = shift @args;
      $first_arg = $arg unless defined $first_arg;
      if ( $arg =~ m/^[a-z]/ ) {
         $subcommand = $arg;
         last;
      } else {
         push @pre_args, $arg;
      }
   }
   if ( $_valid_cmd{$subcommand} ) {
      $subcommand =~ s/-/_/g;
      return bless {
         prog => $prog, 
         pre_args => [ @pre_args ], 
         cmd => $subcommand, 
         args => [ @args ] 
         }, $class;
   } else {
      if ( defined $first_arg ) {
         $subcommand = $first_arg unless defined $subcommand;
         $subcommand = '' unless defined $subcommand;
         print STDERR "$prog: Unknown subcommand '$subcommand'\n";
      }
      return undef;
   }
}


sub do {
   my $self = shift;
   # Using "exec" would be more natural, but it doesn't work as expected on Windows.
   # http://www.perlmonks.org/?node_id=724701
   if ( $^O =~ m/Win32/ ) {
      system(@{$self->args});
      # Need to post-process $? because it's a mix of status bits, and 
      # it seems Windows only allows "main" to return up to 8b its.
      # The $? bottom 8 bits encodes signals, the upper bits encode return status.
      # So $? for the "false" program (returns 1), is actually 256, and then if we exit 256
      # then it's translated back into 0 by Windows. Thus making "false" look like it succeeded!
      my $raw_status = $?; 
      # Fold in the signal error into our 8 bit error range.
      my $processed_status = ($raw_status>>8) | ($raw_status&255);
      exit $processed_status;
   } else {
      exec(@{$self->args});
   }
}


sub run {
   my $self = shift;
   my $cmd = $self->cmd;
   my @args = @{$self->args};
   my $result = eval "\$self->$cmd(\@args)";
   if ($@) {
      return 0;
   } else {
      return $result;
   }
}

sub env {
   my ($self,@args) = @_;
   if ( $#args == 0 && ($args[0] =~ m/.aocx$/i || $args[0] =~ m/.aoco$/i ) ) {
      my $result = $self->binedit($args[0],'print','.acl.compilation_env');
      print "\n";  # "binedit print" does not append the newline
      return $result;
   }
   print STDERR $self->prog." env: Unrecognized options: @args\n";
   return undef;
}

sub version {
   my ($self,@args) = @_;
   if ( $#args < 0 ) {
      my $banner = acl::Env::is_sdk() ? 'Intel(R) FPGA SDK for OpenCL(TM), Version 16.1.0 Build 192, Copyright (C) 2016 Intel Corporation' : 'Intel(R) FPGA Runtime Environment for OpenCL(TM), Version 16.1.0 Build 192, Copyright (C) 2016 Intel Corporation';
      print $self->prog." 16.1.0.192 ($banner)\n";
   } else {
      if ( $#args == 0 && $args[0] =~ m/.aocx$/i ) {
         my $result = $self->binedit($args[0],'print','.acl.version');
         print "\n";  # "binedit print" does not append the newline
         return $result;
      }
      print STDERR $self->prog." version: Unrecognized options: @args\n";
      return undef;
   }
   return $self;
}

sub report {
   my ($self,@args) = @_;
   my $aocx = undef;
   my $mon = undef;
   my @input_args;
   foreach my $arg ( @args ) {
      my ($ext) = $arg =~ /(\.[^.]+)$/;
      if ( $ext eq '.aocx' ) { $aocx = $arg;} 
      elsif ( $ext eq '.mon' ) { $mon = $arg; }
      else { push(@input_args, $arg); }
   }
   if ( defined $aocx && defined $mon ) {
      my $ACL_ROOT = acl::Env::sdk_root();
      if ( ! -e "$ACL_ROOT/share/lib/java/reportgui.jar" ) {
         print $self->prog." report: Intel(R) FPGA SDK for OpenCL(TM) report application not installed, please reinstall your Intel(R) FPGA SDK for OpenCL(TM).\n";
         return $self;
      }
      if ( ! -e $aocx ) {
         print $self->prog." report: Invalid aocx file supplied: $aocx\n";
         return $self;
      }
      if (! -e $mon ) {
         print $self->prog." report: Invalid profile.mon file supplied: $mon\n";
         return $self;
      }

      # Make sure Java is found and it's NOT from /usr/bin -- likely a wrong version
      my $java_location = acl::File::which_full ("java"); chomp $java_location;
      if ( not defined $java_location ) {
         print $self->prog." report: No java executable found!\n" . 
               $self->prog." report needs java that came with ACDS installation.\n" .
               "Add quartus bin directory to the front of the PATH to solve this problem.\n";
         return $self;
      }
      if ( $java_location =~ "/usr/bin" ) {
         my $java_relative_loc;
         if (acl::Env::is_windows()) {
            $java_relative_loc = "/bin64/jre64/bin";
         } else {
            $java_relative_loc = "/linux64/jre64/bin";
         }
         print $self->prog." report: Found Java is $java_location.\n" . 
               "Report needs java that came with ACDS installation.\n" .
               "Add <quartus_rootdir>" . $java_relative_loc . " to the PATH to solve this problem.\n";
         return $self;
      }
      # By now know that java is on the path and it's the one we need.
      system("java", "-jar", "$ACL_ROOT/share/lib/java/reportgui.jar", $aocx, $mon, @input_args );
   } else {
      print $self->prog." report: Report needs aocx and mon\n";
      return undef;
   }
   return $self;
}


sub analyze_area {
   my ($self, @args) = @_;

   if ( @args == 0 ) {
      print $self->prog . " analyze-area requires an aoco or aocx file.\n";
      return undef;
   }
   
   my $input = $args[0];
   if ( ! -e $input ) {
      print "Input file $input was not found.\n";
      return undef;
   }

   if ( ! $input =~ /\.aoc[xo]$/i or 
        system("aocl binedit $input exists .acl.version") != 0 ) {
      print "File $input is not an aoco/aocx file.\n" .
            "Specify an aoco/aocx file to generate an area report.\n";
      return undef;
   }

   if ( system("aocl binedit $input exists .acl.area.html") != 0 ) {
      print "Failed to generate area report because $input is " .
            "missing area report information.\n" . 
            "Try recompiling the source file.\n";
      return undef;
   }
   
   my $html_out = `aocl binedit $input print .acl.area.html`;
   if ( $html_out =~ /Recompile without -g0 for detailed area breakdown by source line/ ) {
      print "$input was compiled with -g0. Recompile without -g0 for detailed area breakdown.\n";
   }
   
   my $output;
   my $output_name = "$input-area-report.html";
   if ( ! open($output, ">", $output_name) ) {
      print "Failed to create area report output file.\n";
      return undef;
   }

   print $output $html_out;
   print "*****Warning: This feature has been deprecated. It will be\n" .
         "removed in the next release. Please see reports/report.html\n" .
         "in the project directory for the new report.\n\n" .
         "Area report successfully created: $output_name\n";
   return $self;
}


sub vis {
   my ($self,@args) = @_;
   
   if ( $#args >= 0 && ($args[0] =~ m/.aoc[xo]$/i ) ) {
      my $ACL_ROOT = acl::Env::sdk_root();
      my $VIS_BIN = "$ACL_ROOT/bin/vis";
      my $VIS_LIB = "$ACL_ROOT/share/lib/acl_vis/";
      my $AOCL_PATH = "$ACL_ROOT/bin/aocl";
      if ((! -e $VIS_BIN) && (! -e "$VIS_BIN.exe")) {
         print $self->prog." vis: Visualizer application not installed, please reinstall your Intel(R) FPGA SDK for OpenCL(TM).\n";
         return $self;
      }
      if (! -e $VIS_LIB) {
         print $self->prog." vis: Visualizer application missing resources, please reinstall your Intel(R) FPGA SDK for OpenCL(TM).\n";
         return $self;
      }
      if ( ! -e $args[0] ) {
	       print $self->prog." vis: Invalid aocx or aoco file supplied: $args[0]\n";
	       return $self;
      }
      # Temporarily pass a flag to the visualizer binary
      # TODO remove this 
      if ( $#args > 0 ) {
        system($VIS_BIN, $args[0], $VIS_LIB, $AOCL_PATH, $args[1]); 
      }
      else {
        system($VIS_BIN, $args[0], $VIS_LIB, $AOCL_PATH); 
      }
   } 
   else {
      print $self->prog." vis: Visualizer requires aocx or aoco\n";
      return undef;
   }
   return $self;
}


sub _print_or_unrecognized(@) {
   my ($self,$name,$printval,@args) = @_;
   if ( $#args >= 0 ) {
      print STDERR $self->prog." $name: Unrecognized option: $args[0]\n";
      return undef;
   }
   print $printval,"\n";
   return $self
}


sub link_config { shift->_print_or_unrecognized('link-config',acl::Env::host_link_config(@_)); }
sub linkflags { shift->_print_or_unrecognized('linkflags',acl::Env::host_link_config(@_)); }
sub ldflags { shift->_print_or_unrecognized('ldflags',acl::Env::host_ldflags(@_)); }
sub ldlibs { shift->_print_or_unrecognized('ldlibs',acl::Env::host_ldlibs(@_)); }
sub board_path { shift->_print_or_unrecognized('board-path',acl::Env::board_path(@_)); }
sub board_hw_path { 
   my ($self,$variant,@args) = @_;
   unless ( $variant ) {
      print STDERR $self->prog." board-hw-path: Missing a board variant argument\n";
      return undef;
   }
   $self->_print_or_unrecognized('board-hw-path',acl::Env::board_hw_path($variant,@args));
}
sub board_mmdlib { shift->_print_or_unrecognized('board-mmdlib',acl::Env::board_mmdlib(@_)); }
sub board_libs { shift->_print_or_unrecognized('board-libs',acl::Env::board_libs(@_)); }
sub board_link_flags { shift->_print_or_unrecognized('board-libs',acl::Env::board_link_flags(@_)); }
sub board_default { shift->_print_or_unrecognized('board-default',acl::Env::board_hardware_default(@_)); }
sub board_version { shift->_print_or_unrecognized('board-version',acl::Env::board_version(@_)); }
sub board_name { shift->_print_or_unrecognized('board-version',acl::Env::board_name(@_)); }


sub board_xml_test {
   my $self = shift;
   my $aocl = acl::Env::sdk_aocl_exe();
   print " board-path       = ".`$aocl board-path`."\n";
   my $board_version = `$aocl board-version`;
   print " board-version    = $board_version\n";
   print " board-name       = ".`$aocl board-name`."\n";
   my $bd_default = `$aocl board-default`;
   print " board-default    = ".$bd_default."\n";
   print " board-hw-path    = ".`$aocl board-hw-path $bd_default`."\n";
   print " board-link-flags = ".`$aocl board-link-flags`."\n";
   print " board-libs       = ".`$aocl board-libs`."\n";
   print " board-util-bin   = ".acl::Board_env::get_util_bin()."\n";
   if ( $board_version >= 15.1 ) {
     print " board-mmdlib     = ".`$aocl board-mmdlib`."\n";
   }
   return $self;
}

sub map_device_to_phys {
  my ($self, $device) = @_;
  if ( acl::Board_env::get_board_version() < 15.1 ) {
    return $device;
  }

  if ( scalar @device_map < 1 ) {
    my $utilbin = acl::Board_env::get_util_bin();
    my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "diagnostic" : "diagnose";
    check_board_utility_env($self) or return undef;
    my $probe_output = `$utilbin/$util -probe`;
    my @lines = split('\n', $probe_output); 
    foreach my $line (@lines) {
      if ( $line =~ /^DIAGNOSTIC_/ ) {
        next;
      } else { 
        push(@device_map,$line);
      }
    }
  }

  #my ($acl_num) = $device =~ /.*\D+(\d+)$/;
  my ($acl_num) = $device =~ /^acl(\d+)$/;
  if ( defined $acl_num and $acl_num >= 0 and $acl_num < scalar(@device_map) ) {
    return  $device_map[$acl_num];
  } else {
    return $device;
  }
}

sub check_board_utility_env {
  my ($self) = @_;

  # Check that BSP is <= SDK version number
  # This call will force an exit if the version is illegal
  my $bsp_version =  acl::Board_env::get_board_version();

  # Check that we're not in emulator mode
  if (defined $ENV{CL_CONTEXT_EMULATOR_DEVICE_ALTERA})
  {
    printf "%s %s: Can't run board utilities with CL_CONTEXT_EMULATOR_DEVICE_ALTERA set\n", $self->prog, $self->cmd;
    return 0;
  }
  return 1;
}

sub program {
  my ($self,@args) = @_;
  reprogram(@_);
  if ( $? ) { return undef; }
  return $self;
}

# Return full path to fpga_temp.bin
sub get_fpga_temp_bin {
   my $arg = shift @_;
   my $pkg = get acl::Pkg($arg);
   if ( !defined($pkg) ) {
     print "Failed to open file: $arg\n";
     return -1;
   }
   my $hasbin = $pkg->exists_section('.acl.fpga.bin');
   if (not $hasbin )
   {  return ""; }
   my $tmpfpgabin = acl::File::mktemp();
   my $fpgabin = $tmpfpgabin;
   if ( length $tmpfpgabin == 0 ) {
     # In case we fail to get a temp file, use local dir.  Using PID
     # as a uniqifier is safe here since this function is called only
     # once by flash, or once by program, and not both in the same process.
     $fpgabin = "fpga_temp_$$.bin";
   } else {
     $fpgabin .= '_fpga_temp.bin';
   }
   my $gotbin = $pkg->get_file('.acl.fpga.bin', $fpgabin);
   if ( !defined( $gotbin )) {
     print "Failed to extract binary section from file: $arg\n";
     print "  Tried: $fpgabin and $tmpfpgabin\n";
     return "";
   }
   return $fpgabin;
}

sub reprogram {
   my ($self, @args) = @_;
   my $utilbin = acl::Board_env::get_util_bin(); 
   my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "reprogram" : "program";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( defined $command ) {
     print $self->prog." program: Running $util from $utilbin\n";
     # Parse the arguments
     my $device = undef;
     my $aocx = undef;
     my $num_args = @args;
     foreach my $arg ( @args ) {
        my ($ext) = $arg =~ /(\.[^.]+)$/;
        if ( $ext eq '.aocx' ) { $aocx = $arg;} 
        else { $device = map_device_to_phys($self,$arg); }
     }
     # If arguments not valid, print help/usage message.
     if ( $num_args != 2 or !defined($aocx) or !defined($device)) {
        my $help = new acl::Command($self->prog, qw(help program));
        $help->run();
        return undef;
     }
     # Get .bin from the AOCX file and call reprogram with that
     my $fpgabin = get_fpga_temp_bin($aocx);
     if ( length $fpgabin == 0 ) { printf "%s program: Program failed. Error reading aocx file.\n", $self->prog; return undef; }

     if ( acl::Board_env::get_board_version() > 15.0)
     { 
       # new 15.1 boards 
       delete $ENV{CL_CONTEXT_COMPILER_MODE_ALTERA};
       # setting the environment variable below is for A10 boards, it will cause the runtime environment to ignore the board name when attempting to reprogram
       $ENV{ACL_PCIE_PROGRAM_SKIP_BOARDNAME_CHECK}='1';
       system("$utilbin/$util","$device",$fpgabin,$aocx);
     } else {
       # old pre-15.1 boards
       system("$utilbin/$util","$device",$fpgabin);
     }         
     #remove the file we ouput
     unlink $fpgabin;

     if ( $? ) { printf "%s program: Program failed.\n", $self->prog; return undef; }
     return $self;
     print $self->prog." program: Running program from $utilbin\n";
     system("$utilbin/$util",$device,@args);
     if ( $? ) { printf "%s program: Program failed.\n", $self->prog; return undef; }
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No programming routine supplied.                                    \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to load a new image on to the FPGA.     \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub flash {
   my ($self, @args) = @_;
   my $utilbin = acl::Board_env::get_util_bin(); 
   my $util = "flash";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( defined $command ) {
     print $self->prog." flash: Running $util from $utilbin\n";
     # Parse the arguments
     my $device = undef;
     my $aocx = undef;
     my $num_args = @args;
     foreach my $arg ( @args ) {
        my ($ext) = $arg =~ /(\.[^.]+)$/;
        if ( $ext eq '.aocx' ) { $aocx = $arg;} 
        else { $device = map_device_to_phys($self,$arg); }
     }
     # If arguments not valid, print help/usage message.
     if ( $num_args != 2 or !defined($aocx) or !defined($device)) {
        my $help = new acl::Command($self->prog, qw(help flash));
        $help->run();
        return undef;
     }
     # Get .bin from the AOCX file and call flash with that
     my $fpgabin = get_fpga_temp_bin($aocx);
     if ( length $fpgabin == 0 ) { printf "%s flash: Flashing failed. Error reading aocx file.\n", $self->prog; return undef; }

     system("$utilbin/$util","$device",$fpgabin);
     #remove the file we ouput
     unlink $fpgabin;

     if ( $? ) { printf "%s flash: Program failed.\n", $self->prog; return undef; }
     return $self;
     print $self->prog." flash: Running flash from $utilbin\n";
     system("$utilbin/$util",$device,@args);
     if ( $? ) { printf "%s flash: Program failed.\n", $self->prog; return undef; }
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No flash routine supplied.                                    \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to load a new image on to the FPGA.     \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub diagnose {
  my ($self,@args) = @_;
  diagnostic(@_);
  if ( $? ) { return undef; }
  return $self;
}

sub diagnostic {
   my ($self,@args) = @_;
   my $utilbin = acl::Board_env::get_util_bin();
   my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "diagnostic" : "diagnose";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( ! defined $command ) {
      print "--------------------------------------------------------------------\n";
      print "No board diagnose routine supplied.                               \n";
      print "Please consult your board manufacturer's documentation or support   \n";
      print "team for information on how to debug board installation problems.   \n";
      print "--------------------------------------------------------------------\n";
      return $self;
   }

   print $self->prog." diagnose: Running $util from $utilbin\n";

   if ( scalar @args == 0 and acl::Board_env::get_board_version() >= 15.1 ) {
     # List all devices and statistics if no arguments
     map_device_to_phys($self,"acl0"); # Dummy map to force population of device_map
     if ( scalar(@device_map) < 1 ) { printf "%s diagnose: BSP advertises 0 devices to connect to.\n", $self->prog,; return undef; }
     my $error = 0;
     my $firsterror = "";
     for (my $i=0; $i<scalar(@device_map); $i++) {
       my $logical_device = "acl$i";
       my $phys_device = map_device_to_phys($self, $logical_device);
       my $probe_out = `$utilbin/$util -probe $phys_device`;
       if ( $probe_out =~ /DIAGNOSTIC_PASSED/ ) {
         print "\n------------------------- $logical_device -------------------------\n";
         print "$probe_out";
         print "---------------------------------------------------------\n\n";
       } else {
         $error++;
         if ( $error == 1 ) {
           $firsterror = $probe_out;
         }
       }
     }
     if ( $error == scalar(@device_map) ) { printf "%s diagnose: failed %d times. First error below:\n%s\n", $self->prog, $error, $firsterror; return undef; }

   } else {
     # Otherwise call BSP diagnose with device args remapped to physical
     for (my $i=0; $i<scalar(@args); $i++) {
       $args[$i] = map_device_to_phys($self,$args[$i]);
     }

     system("$utilbin/$util",@args);
     if ( $? ) { printf "%s diagnose: failed.\n", $self->prog; return undef; }
   }
   return $self;
}

sub setup_acd {
   my $generic_error_message = "Unable to set up ACD. Please contact your board vendor or see section \"Linking Your Host Application to the Khronos ICD Loader Library\" of the Programming Guide for instructions on manual setup.\n";
   
   my $acl_board_path = acl::Board_env::get_board_path();
   my $mmdlib = acl::Board_env::get_mmdlib_if_exists();
   
   if(not defined $mmdlib) {
      print "Warning: 'mmdlib' is not defined in $acl_board_path/board_env.xml.\n$generic_error_message";
      return;
   }
   
   #split the paths out based on the comma separator, then insert the acl board path in place of '%b':
   my @lib_paths = split(/,/, $mmdlib);
   my $board_path_indicator = '%b';
   s/$board_path_indicator/$acl_board_path/ for @lib_paths;
   
   if ($^O eq "linux") {
      #create the target path (if it doesn't exist) and move there:
      my @target_path = ('opt', 'Altera', 'OpenCL', 'Boards');
      
      chdir "/"; #start at the root
      my $full_dir = ""; #used for giving a sensible error message
      #build the target path:
      for my $dir (@target_path) {
         $full_dir = $full_dir . "/" . $dir;
         if(!(-d $dir)) {
            mkdir $dir or print "Couldn't create directory '$full_dir'\nERROR: $!\n$generic_error_message" and return;
         }
         chdir $dir;
      }
      
      #now print the paths to the .acd file:
      my $board_env_name = acl::Board_env::get_board_name();
      my $acd_list_path = "$board_env_name.acd";
      
      open(my $filehandle, ">", $acd_list_path) or print "Couldn't open '$full_dir/$acd_list_path' for output\n$generic_error_message" and return;
      for my $lib_path (@lib_paths) {
         print $filehandle $lib_path . "\n";
      }
      close $filehandle;
      
   } elsif ($^O eq "MSWin32") {
      my $reg_key = 'HKEY_LOCAL_MACHINE\Software\Altera\OpenCL\Boards';
      
      #Add the library paths:
      for my $lib_path (@lib_paths) {
         
         #This is fun, replace forward slashes with back slashes:
         $lib_path =~ s/\//\\/g;
         
         if($lib_path) {
            #Adds the registry entry.
            #/v $lib_path to specify a value name (in this case, the name of the value is the path to the dll)
            #/t REG_DWORD to specify the value type
            #/d 0000 for the value data
            #/f to force overwrite in case the value already exists
            system ("reg add $reg_key /v $lib_path /t REG_DWORD /d 0000 /f") == 0 or print "Unable to edit registry entry\n$generic_error_message" and return;
         }
      }
   } else {
      print "No ACD setup proceedure defined for OS '$^O'.\n$generic_error_message";
      return;
   }
}

sub install {
   my ($self,@args) = @_;
   my $utilbin = acl::Board_env::get_util_bin();
   my $util = "install";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( defined $command ) {
     print $self->prog." $util: Running $util from $utilbin\n";
     system("$utilbin/$util",@args);
     if ( $? ) { 
       printf "%s $util: failed.\n", $self->prog; 
       return undef; 
     } else {
       setup_acd();
     }
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No board installation routine supplied.                             \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to properly install your board.         \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub uninstall {
   my ($self,@args) = @_;
   my $utilbin = acl::Board_env::get_util_bin();
   my $util = "uninstall";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( defined $command ) {
     print $self->prog." $util: Running $util from $utilbin\n";
     system("$utilbin/$util",@args);
     if ( $? ) { printf "%s $util: failed.\n", $self->prog; return undef; }
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No board uninstallation routine supplied.                             \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to properly uninstall your board.         \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub binedit {
   my ($self,@args) = @_;
   system(acl::Env::sdk_pkg_editor_exe(),@args);
   return undef if $?;
   return $self;
}

sub library {
   my ($self,@args) = @_;
   system(acl::Env::sdk_libedit_exe(),@args);
   return undef if $?;
   return $self;
}

sub hash {
   my ($self,@args) = @_;
   system(acl::Env::sdk_hash_exe(),@args);
   return undef if $?;
   return $self;
}


sub _cflags_include_only {
   my $ACL_ROOT = acl::Env::sdk_root();
   return "-I$ACL_ROOT/host/include";
}

sub _get_cross_compiler_include_directories {
   my ($cross_compiler) = @_;

   my $includes = undef;
   my $ACL_ROOT = acl::Env::sdk_root();
   my $output = `$cross_compiler -v -c $ACL_ROOT/share/lib/c/includes.c -o /dev/null 2>&1`;
   $? == 0 or print STDERR "Error determing cross compiler default include directories\n";
   my $add_includes = 0;
   my @lines = split('\n', $output); 
   foreach my $line (@lines) {
      if ($line =~ /^#include <\.\.\.> search starts here:/) {
         $add_includes = 1;
      } elsif ($line =~ /^End of search list./) {
         $add_includes = 0;
      } elsif ($add_includes) {
         $includes .= " -I".$line;
      }
   }
   return $includes." ";
}

sub compile_config {
   my ($self,@args) = @_;
   my $extra_flags = undef;
   while ( $#args >= 0 ) {
      my $arg = shift @args;
      if ( $arg eq '--arm-cross-compiler' ) {
         if (acl::Env::is_windows()) {
            print STDERR $self->prog." compile-config: --arm-cross-compiler is not supported on Windows.\n";
            return undef;
         }
         if ($#args >= 0) {
            my $cross_compiler = shift @args;
            $extra_flags = _get_cross_compiler_include_directories($cross_compiler);
         } else {
            print STDERR $self->prog." compile-config: --arm-cross-compiler requires an argument.\n";
            return undef;
         }
      } elsif ( $arg eq '--arm' ) {
         # Just swallow the arg.
      } else {
         print STDERR $self->prog." compile-config: unknown option $arg.\n"; 
         return undef;
      }
   }
   my $board_flags = acl::Board_env::get_xml_platform_tag_if_exists("compileflags");
   print $extra_flags . _cflags_include_only(). " $board_flags" . "\n";
   return $self;
}
sub cflags {
   my ($self,@args) = @_;
   compile_config(@_);
   return $self;
}


sub example_makefile {
   my ($self,@args) = @_;
   my $help = new acl::Command($self->prog, qw(help example-makefile), @args);
   $help->run();
   return $self;
}


sub makefile {
   my ($self,@args) = @_;
   my $help = new acl::Command($self->prog, qw(help example-makefile), @args);
   $help->run();
   return $self;
}

sub AUTOLOAD {
   my $self = shift;
   my $class = ref($self) or die "$self is not an object";
   my $name = $AUTOLOAD;
   $name =~ s/^.*:://;
   my $result = $${self}{$name};
   return $result;
}


sub help {
   my ($self,$topic,@args) = @_;
   my $prog = $self->prog;

   my $sdk_root_name = acl::Env::sdk_root_name();
   my $is_sdk = acl::Env::is_sdk();
   my $sdk = $is_sdk ? "SDK" : "RTE";
   my $sdk_first_mention = $is_sdk ? "SDK" : "Runtime Environment (RTE)";
   my $target_arm = ($#args >= 0) and ($args[0] eq '--arm');

   my $use_aoc_note= <<USE_AOC_NOTE;
Note: Use the separate "aoc" command to compile your OpenCL kernel programs.
USE_AOC_NOTE
   my $use_aoc_in_rte_note= <<USE_AOC_IN_RTE_NOTE;
Note: Use the "aoc" command from the Intel(R) FPGA SDK for OpenCL(TM) to compile
your OpenCL kernel programs.
USE_AOC_IN_RTE_NOTE
   my $aoc_note = $is_sdk ? $use_aoc_note : $use_aoc_in_rte_note;

   my $loader_advice =<<LOADER_ADVICE;
   Additionally, at runtime your host program must run in an enviornment
   where it can find the shared libraries provided by the Intel(R) FPGA $sdk for
   OpenCL(TM).  

   For example, on Windows the PATH environment variable should include
   the directory %$sdk_root_name%/host/windows64/bin.

   For example, on Linux the LD_LIBRARY_PATH environment variable should
   include the directory \$$sdk_root_name/host/linux64/lib.

See also: $prog example-makefile
LOADER_ADVICE

   my $host_compiler_options = <<HOST_COMPILER_OPTIONS;
   --msvc, --windows       Show link line for Microsoft Visual C/C++.
   --gnu, -gcc, --linux    Show link line for GCC toolchain on Linux.
   --arm                   Show link line for cross-compiling to arm.
HOST_COMPILER_OPTIONS

my $makefile_help_arm = <<MAKEFILE_EXAMPLE_HELP_ARM_ONLY;

Example GNU makefile cross-compiling to ARM SoC from Linux or Windows, with 
Linaro GCC cross-compiler toolchain:

CROSS-COMPILER=arm-linux-gnueabihf-
AOCL_COMPILE_CONFIG=\$(shell $prog compile-config --arm)
AOCL_LINK_CONFIG=\$(shell $prog link-config --arm)

host_prog : host_prog.o
	\$(CROSS-COMPILER)g++ -o host_prog host_prog.o \$(AOCL_LINK_CONFIG)

host_prog.o : host_prog.cpp
	\$(CROSS-COMPILER)g++ -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)


MAKEFILE_EXAMPLE_HELP_ARM_ONLY

my $makefile_help = <<MAKEFILE_EXAMPLE_HELP;

The following are example Makefile fragments for compiling and linking
a host program against the host runtime libraries included with the 
Intel(R) FPGA $sdk for OpenCL(TM).


Example GNU makefile on Linux, with GCC toolchain:

AOCL_COMPILE_CONFIG=\$(shell $prog compile-config)
AOCL_LINK_CONFIG=\$(shell $prog link-config)

host_prog : host_prog.o
	g++ -o host_prog host_prog.o \$(AOCL_LINK_CONFIG)

host_prog.o : host_prog.cpp
	g++ -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)


Example GNU makefile on Windows, with Microsoft Visual C++ command line compiler:

AOCL_COMPILE_CONFIG=\$(shell $prog compile-config)
AOCL_LINK_CONFIG=\$(shell $prog link-config)

host_prog.exe : host_prog.obj
	link -nologo /OUT:host_prog.exe host_prog.obj \$(AOCL_LINK_CONFIG)

host_prog.obj : host_prog.cpp
	cl /MD /Fohost_prog.obj -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)


MAKEFILE_EXAMPLE_HELP

   my %_help_topics = (

     'example-makefile', ($target_arm ? $makefile_help_arm : $makefile_help . $makefile_help_arm),

     'compile-config', <<COMPILE_CONFIG_HELP,

$prog compile-config - Show compilation flags for host programs


Usage: $prog compile-config


Example use in a GNU makefile on Linux:

   AOCL_COMPILE_CONFIG=\$(shell $prog compile-config)
   host_prog.o :
   	g++ -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)

See also: $prog example-makefile

COMPILE_CONFIG_HELP


      'link-config', <<LINK_CONFIG_HELP,

$prog link-config - Show linker flags and libraries for host programs.


Usage: $prog link-config [options]

   By default the link line for the current platform are shown.


Description:

   This subcommand shows the linker flags and the list of libraries
   required to link a host program with the runtime libraries provided
   by the Intel(R) FPGA $sdk for OpenCL(TM).

   This subcommand combines the functions of the "ldflags" and "ldlibs"
   subcommands.

$loader_advice

Options:
$host_compiler_options

LINK_CONFIG_HELP


      'ldflags', <<LDFLAGS_HELP,

$prog ldflags - Show linker flags for building a host program.


Usage: $prog ldflags [options]

   By default the linker flags for the current platform are shown.


Description:

   This subcommand shows the general linker flags required to link 
   your host program with the runtime libraries provied by the 
   Intel(R) FPGA $sdk for OpenCL(TM).

   Your link line also must include the runtime libraries from the Intel(R) FPGA
   $sdk for OpenCL(TM) as listed by the "ldlibs" subcommand.

$loader_advice

Options:
$host_compiler_options

LDFLAGS_HELP


      'ldlibs', <<LDLIBS_HELP,

$prog ldlibs - Show list of runtime libraries for building a host program.


Usage: $prog ldlibs [options]

   By default the libraries for the current platform are shown.


Description:

   This subcommand shows the list of libraries provided by the 
   Intel(R) FPGA $sdk for OpenCL(TM) that are required link a host program.

   Your link line also must include the linker flags as listed by 
   the "ldlfags" subcommand.

$loader_advice

Options:
$host_compiler_options

LDLIBS_HELP

      'program', <<BOARD_PROGRAM_HELP,

$prog program - Configures a new FPGA design onto your board


Usage: $prog program <device_name> <file.aocx>

   Supply the .aocx file for the design you wish to configure onto 
   the FPGA.  You need to provide <device_name> to specify the FPGA 
   device to configure with. 

Description:

   This command downloads a new design onto your FPGA.
   This utility should not normally be used, users should instead use 
   clCreateProgramWithBinary to configure the FPGA with the .aocx file.

BOARD_PROGRAM_HELP

      'flash', <<BOARD_FLASH_HELP,

$prog flash - Initialize the FPGA with a specific startup configuration.


Usage: $prog flash <device_name> <file.aocx>

   Supply the .aocx file for the design you wish to set as the default
   configuration which is loaded on power up.

Description:

   This command initializes the board with a default configuration
   that is loaded onto the FPGA on power up.  Not all boards will 
   support this, check with your board vendor documentation.

BOARD_FLASH_HELP

      'diagnose', <<BOARD_DIAGNOSTIC_HELP,

$prog diagnose - Run your board vendor's test program for the board.


Usage: $prog diagnose [<device_name>]

Description:

   This command executes a board vendor test utility to verify the 
   functionality of the device specified by <device_name>.  

   If <device_name> is not specified, it will show a list of currently 
   installed devices that are supported by the board package.

   The utility should output the text DIAGNOSTIC_PASSED as the final 
   line of output.  If this is not the case (either that text is absent, 
   the test displays DIAGNOSTIC_FAILED, or the test doesn't terminate),
   then there may be a problem with the board.


BOARD_DIAGNOSTIC_HELP

      'install', <<BOARD_INSTALL_HELP,

$prog install -  Installs a board onto your host system.


Usage: $prog install

Description:

   This command installs a board's drivers and other necessary
   software for the host operating system to communicate with the
   board.  For example this might install PCIe drivers.

BOARD_INSTALL_HELP

      'uninstall', <<BOARD_UNINSTALL_HELP,

$prog uninstall -  Installs a board onto your host system.


Usage: $prog uninstall

Description:

   This command uninstalls a board's drivers and other necessary
   software for the host operating system to communicate with the
   board.  For example this might uninstall PCIe drivers.

BOARD_UNINSTALL_HELP

      'report', <<PROFILE_REPORT_HELP,

$prog report - Parse the profiled aocx and mon file and display the
               profiler GUI.


Usage: $prog report <file.aocx> <profile.mon>

Description:

   Supply the .aocx file for the design that was profiled and
   the generated .mon file from the host execution. It is
   assumed that --profile was enabled when generating the
   .aocx file (see aoc options for information on --profile).

PROFILE_REPORT_HELP

      'analyze-area', <<ANALYZE_AREA_HELP,
     
$prog analyze-area - **This feature has been deprecated. It will be removed 
                     in the next release. Please see reports/report.html
                     in the project directory for the new report.**
                     Generate an HTML table containing area usage by source 
                     code line. 
               

Usage: $prog analyze-area <file.aoco/aocx>

Description:
   
   This command generates an HTML table containing area usage
   broken down by source code line from the aoco or aocx file.
   The aoco or aocx file must not be compiled with the -g0 flag.

ANALYZE_AREA_HELP

      'vis', <<VISUALIZER_APPLICATION_HELP,

$prog vis - Runs the Visualizer application.


Usage: $prog vis <file.aoco/aocx>

Description:
   
   This command takes the aoco or aocx file provided and starts up 
   the Visualizer tool for that design. 

VISUALIZER_APPLICATION_HELP

      'env', <<ENV_HELP,

$prog env - Show the compilation environment of a binary.


Usage: $prog env <file.aoco/aocx>

Description:

   This command takes the aoco or aocx file provided and displays
   the compiler's input arguments and environment for that design.

ENV_HELP

      help => <<GENERAL_HELP,

$prog - Intel(R) FPGA $sdk_first_mention for OpenCL(TM) utility command.


$aoc_note

Subcommands for building your host program:

   $prog example-makefile  Show Makefile fragments for compiling and linking
                          a host program.
   $prog makefile          Same as the "example-makefile" subcommand.

   $prog compile-config    Show the flags for compiling your host program.
   $prog link-config       Show the flags for linking your host program with the
                          runtime libraries provided by the Intel(R) FPGA $sdk for OpenCL(TM).
                          This combines the function of the "ldflags" and "ldlibs"
                          subcomands.
   $prog linkflags         Same as the "link-config" subcommand.

   $prog ldflags           Show the linker flags used to link your host program
                          to the host runtime libraries provided by the Intel(R) FPGA $sdk
                          for OpenCL(TM).  This does not list the libraries themselves.

   $prog ldlibs            Show the list of host runtime libraries provided by the 
                          Intel(R) FPGA $sdk for OpenCL(TM).

Subcommands for managing an FPGA board:

   $prog program           Configure a new FPGA image onto the board.  

   $prog flash             [If supported] Initialize the FPGA with a specified
                          startup configuration.

   $prog install           Install your board into the current host system.

   $prog uninstall         Uninstall your board from the current host system.

   $prog diagnose          Run your board vendor's test program for the board.

General:

   $prog report            Parse the profile data and display GUI.
   $prog analyze-area      Generate an HTML table containing the area report. (Deprecated)
   $prog library           Manage OpenCL libraries. Run "$prog library help" for more info.
   $prog env               Show the compilation environment of a binary
   $prog version           Show version information.
   $prog help              Show this help.
   $prog help <subcommand> Show help for a particular subcommand.
 
GENERAL_HELP
   );

   $_help_topics{'linkflags'} = $_help_topics{'link-config'};
   $_help_topics{'linkflags'} =~ s/link-config/linkflags/g;

   $_help_topics{'cflags'} = $_help_topics{'compile-config'};
   $_help_topics{'cflags'} =~ s/compile-config/cflags/g;

   $_help_topics{'makefile'} = $_help_topics{'example-makefile'};

   if ( defined $topic ) {
      my $output = $_help_topics{$topic};
      if ( defined $output ) { print $output; }
      else { print $_help_topics{'help'}; return undef; }
   } else {
      print $_help_topics{'help'};
   }
   return $self;
}


1;
