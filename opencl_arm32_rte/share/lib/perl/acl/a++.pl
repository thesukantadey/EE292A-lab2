# (C) 1992-2015 Altera Corporation. All rights reserved.                         
# Your use of Altera Corporation's design tools, logic functions and other       
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Altera MegaCore Function License Agreement, or other applicable     
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Altera and sold by   
# Altera or its authorized distributors.  Please refer to the applicable         
# agreement for further details.                                                 
    


# Altera SDK for HLS compilation.
#  Inputs:  A mix of sorce files and object filse
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       a++ foo.cpp bar.c fum.o -lm -I../inc
#     Generates:     
#        Subdirectory a.project  including key files:
#           *.v
#           <something>.qsf   - Quartus project settings
#           <something>.sopc  - SOPC Builder project settings
#           kernel_system.tcl - SOPC Builder TCL script for kernel_system.qsys 
#           system.tcl        - SOPC Builder TCL script
#
# vim: set ts=2 sw=2 et

      BEGIN { 
         unshift @INC,
            (grep { -d $_ }
               (map { $ENV{"ALTERAOCLSDKROOT"}.$_ }
                  qw(
                     /host/windows64/bin/perl/lib/MSWin32-x64-multi-thread
                     /host/windows64/bin/perl/lib
                     /share/lib/perl
                     /share/lib/perl/5.8.8 ) ) );
      };


use strict;
require acl::File;
require acl::DSE;
require acl::Pkg;
require acl::Env;

my $prog = 'a++';
my $return_status = 0;

#Filenames
my @source_list = ();
my @object_list = ();
my @tmpobject_list = ();
my @fpga_IR_list = ();
my @tb_IR_list = ();
my @cleanup_list = ();

my $project_name = undef;
my $project_log = undef;
my $executable = undef;
my $board_variant=undef;
my $family = undef;
my $family_legacy = undef;
my $optinfile = undef;
my $pkg = undef;

#directories
my $orig_dir = undef; # path of original working directory.
my $g_work_dir = undef; # path of the project working directory as is.

# Executables
my $clang_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $link_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-link";
my $llc_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $sysinteg_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/system_integrator";

#Flow control
my $emulator_flow = 0;
my $simulator_flow = 0;
my $RTL_only_flow_modifier = 0;
my $object_only_flow_modifier = 0;
my $soft_ip_c_flow_modifier = 0; # Hidden option for soft IP compilation
my $macro_type_string = "";
my $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
my $cosim_debug = 0;

# Quartus Compile Flow
my $qii_flow = 0;
my $qii_vpins = 0;
my $qii_io_regs = 0;
my $qii_device = undef;
my $qii_device_legacy = undef;
my $qii_seed = undef;
my $qii_fmax_constraint = 0;

# Flow modifier
my $target_x86 = 0; # Hidden option for soft IP compilation to target x86

#Output control
my $verbose = 0; # Note: there are three verbosity levels now 1, 2 and 3
my $disassemble = 0; # Hidden option to disassemble the IR
my $dotfiles = 0;
my $save_tmps = 0;
my $debug_symbols = 0;      # Debug info enabled?

#Command line support
my @cmd_list = ();
my @parseflags=();
my @linkflags=();
my @additional_opt_args   = (); # Extra options for opt, after regular options.
my @additional_llc_args   = ();
my @additional_sysinteg_args = ();

my $opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkzwewi22etqs0o0cvorlvczrk7mipp8xd3egwiyx713svzw3kmlt8clxdbqoypaxbbyw0oygu1nsyzekh3nt0x0jpsmvypfxguwwdo880qqk8pachqllyc18a7q3wp12j7eqwipxw13swz1bp7tk71wyb3rb17frk3egwiy2e7qjwoe3bkny8xrrdbq1w7ljg70g0o1xlbmupoecdfluu3xxf7l3dogxfs0lvm7jlzqgdouchorlvcvxafq187frk37qvz7xlkms8patk72tfxmxkumowos2ho0s0onrwctgfpttd3nuwx72kmncwosxbbyw0o0re1mju7atjonupbvghbtijzyrfbwtfmiretqsjoehdorlvc1rh3ncjzmxbbyw0o22eonu8pehd72tfxmgssm80oyrgkwrpii2wctgfpttdqnq0bvgsom7jzerj38uui3gw1nsvz03ghll8cyrjmn8w7ljg70t8zmxuolsypscfqnldx0jpsmvjoy2kh0t8zr2wcnay7atj3mj8c0jpsmv8zrgfh0sdmirezquyzy1bknyvbzga3loype2sbyw0op2qoqk8zdch3quu3xxfqm38p32vs0rjzvgu1qjwzkhhcluu3xxf1q30o12hm0kjz7xuols0outkmlh8xc2a33czpyrkfwg8z7xlbmryzw3bkny0blxa3nbvzrxdu0wyi880qqkvok3h7qq8x2gh7qxvzt8vs0rpiiru3lkjpfhjqllyc0jpsmv0or2hh0rpopxl1ma8pfcvorlvcqgskq10pggju7ryomx713svz23kmnjvbcxfumb0olxbbyw0oprlemyy7atj1mlwb7rjbqb17frkh0q0ozx713svzdthhlky3xxfblijo02hc7rvi7jlzmr0p23k3qejxvrdbti0z3vbbyw0oprlemyy7atjoqlvbtgscnvwpt8vs0rpiiru3lkjpfhjqllyc0jpsmvypfxjo7t8ztx713svzdthhlky3xxfuqcypd2g38uui3xleqs0oekh3ltycvgdcnzvpfxbbyw0omgyqmju7atjsntyxmrkuniwomxbbyw0otrezmy07ekh3nedxqrj7mi8pu2hs0uvm7jlzmfyofcdorlvcyrsmncyzq2hs0yvm7jlzqkjp2hdolq8cygdcmczpyxfm7wvz1rwbmr8pshh72tfxmrd7ncw7ljg70tjo32wctgfpttdqnq0bvgsom7jzerj38uui32qqquwotthsly8xxgd33czpyrfcegpiy20qqkwze3jzntfxmrkmni0odxduehdotx713svzqchhly8cvrd7mcw7ljg70rwiiru3layz2tkoluu3xxfmmbdo12hbwgvm7jlzqkjpahfoljwb18a7mzvp1xjbyw0obrl7nuy7atjzmly3xxfuqi0o12hs0gpi3ructgfptchhngyclgpsmvwogxfb0gvm7jlzqrdp2thflqy3xxf7qzyzfggbwe0z880qqkwzqhfomt0318a7qovpdxfbyw0ot2qumywpkhkqquu3xxfhmvjo82k38uui3xleqs0oekh3nhdxlxahqow7ljg70gpizxutqddzbtjbnr0318a7m8jzyxf38uui3rwmns07ekh3nqycbxf3n7vp3xd38uui32qqquwotthsly8xxgd33czpyghb7evz7jlzmr0p23kmlt8xxxd33czpyxj77uvm7jlzqjwzt3k72tfxmxkumowos2ho0s0onrwctgfpt3gknjwbmxakqvypf2j38uui3ru3nu8p83bknywc1gfcmczpyxfm7wjzoxyknyyz3cvorlvc3rafqvyzsxj70uvm7jlzqkjpatdzmqyclxdbqb17frkm0t8zr2q1mu07ekh3ntdczgpsmvwod2hswkdor20qqk8z2tkorlvc72a1qoyi82h7etfmirebmajou3a3mtfxmgssqoypf2j38uui3glemuyp23kzquu3xxfkmcdow2jm7ujzeguqmju7atjqllwb12kombjzlrf38uui3xw7mtyoecvorlvcw2kfmovpm2j7ekpow2qzqu07ekh3nuvcvgpsmv0pd2kc0uui3ru3lspoe3bkny8xxrjmnzpp82h70gdmirebmgwzy1bkny0x72acqo8zljg70uyobrebmawp3cvorlvcy2k1qijoergm7edmire1mh8pt3jflqvb0jpsmv0pdrdbwg0ooglmnju7atjznyyc0jpsmv0pdrdbwg0ooglznr07ekh3nuwxtgfun887frkm7udiogy1qgfpt3honqy3xxfuqi0o12hs0gpi3ructgfpthdonqjxrgdbtijzdrgm0uui32ezqkyz3tdonj0318a7qcjzlxbbyw0otrebma8z2hdolkwx0jpsmv0zy2j38uui3xuolddo2kdonr0318a7q88zargo7udmirekms8p03gmlq8xagfcnzvpf2vs0r0zwrlolgvoy1bkny0blxakmi0olxfm7qyz880qqk8zwtjoluu3xxfhmivp32vs0r0zb2lcna8pl3a72tfxmrktmz87frk70wpop2wzlk8patk72tfxmxkumowos2ho0s0onrwctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3lr8xdgj3nczpygkuwk0o1ru3lu07ekh3lqyx1gabtijz8xfh0qjzw2wonju7atjbmtpbz2dulb17frk1wkjzr2qoqrwoecd1ml0b7xd1q3ypdgg38uui3rwmns07ekh3ltjcrgjbqb17frkc0rdo880qqkvok3h7qq8x2gh7qxvzt8vs0rjitxyolrvz03gbnf0318a7mzpp8xd70wdi22qqqgy7atjknly3xxfolb17frk77rpop2eoldpie3bknywx72kzmc87frk10ywor2w7qjwoetd72tfxmxk7mb0prgfm7uvzpx713svzwtjoluu3xxfomzwinxfbyw0o22q3lk8z3cf3quu3xxfhmivolgf77jpiwrehmju7atj3my8cvgfmnzdilxbbyw0oirlolawp3cvorlvc8xfbqb17frk1wu0o7x713svzqhfkluu3xxfcmv8zt8vs0rpiiru3lkjpfhjqllyc0jpsmvwo1rgzwgpoz20qqkjzdth1nuwx18a7mo8zaxbbyw0oygueqhpou3horlvc3rafqvyzs2vs0rdi72l13svz7tdmnryc0jpsmv0o12ho7qpop20qqkypucfeluu3xxfzq2ppt8vs0r0zb2lcna8pl3aorlvc2rk33czpyxj70uvm7jlzqddpw3kemjjb7rk3nzppwxbbyw0oq2qkqkypy1bknywblgfsm8pzdgfk0uui3xuolddp0hk72tfxmrafmiwoljg70gpizxutqddzbcvorlvcvxf7n8yzt8vs0rdi7xleqs0oy1bknydb12kuqxyit8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7we0otrubmju7atj1lydclgd1nczpy2kswwwiw2e3lg07ekh3ltjxygpsmvjzerjbyw0o2gemmuyz1cvorlvcn2k1qijzh2vs0r0ooglmlgpo33ghllp10jpsmv0zy2j38uui32qqquwotthsly8xxgd33czpygdb0rjzogukmeyzekh3nwycl2abqow7ljg7wjdor2qmqw07ekh3nrdbxrzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frko7u8zbgwknju7atj1mtyxc2jbmczpyxjb0tjo7jlzquwoshdonj0318a7qcjzlxbbyw0ol2wolddzbcvorlvcbgdmnx8zljg7wh8z7xwkqk8z03kzntfxmxkcnidolrf38uui3xwzqg07ekh3nedxqrj7mi8pu2hs0uvm7jlzmuyz8chqny8cygdbtijzsrfbetfmirebmgvzecvorlvcvgs7mow7ljg7wewioxu13svztthsly8xxgd33czpyxgu0rdi880qqkdoehdqlr8v0jpsmv0pdrg37uui3xyold0otthoqlwb18a7mbppfrgc7tjz7x713svzthj7quu3xxfoncdoggjuetfmirekmsvo0tjhnqpcz2abqb17frkzwjyi880qqkvok3h7qq8x2gh7qxvzt8vs0rdi7gu7qgpoecfoqjdx0jpsmvjog2g3eepin2tzmhjzy1bknywxcxjbq8jo02hc7rvi880qqkjznhh72tfxmrjmnzpog2kh0uui32lbmr0py1bknywcmgd33czpygdbwgpin2tctgfpthdoltybmgdbtijz12j77wdzrre1qu07ekh3ltvc1rzbtijz72jm7qyokx713svzuckunhvbygpsmvjoggsb0gvm7jlzqu8pfcdfnedcfxfomxw7ljg7wewiq2wolujokcf3le0318a7mvwprggs0uji7jlzmk8z2hdqntpb18a7mzpp82jmekpioglctgfptchqnyyx0jpsmv8p3xj38uui32eqmsjp03jzmty3xxf7miyzs2j77rpiirw13svzrthoqlwcqrzbtijz32h70ldmireuqgypekh3nyjxx2dumxw7ljg7wjdor2qmqw07ekh3lq8xmga33czpyrdu0q0ozx713svzdthmltvbyxamncjom2sh0uvm7jlzmajoqchqllvb12kclb17frkm7udi1xy1mu8puchqldyc0jpsmv0zy2j38uui3gebmupok3k1mjwbfrabqb17frkc0rdo880qqkpoecfengjb3gscqb17frkz7qyi880qqkjoshdtnewb1gabtijzgggcegpiirukqkvoekh3lqjxtgdmncdot8vs0rdi72lemu8i3cf1mt8cbgssmxw7ljg7wewi1xwznrjp23k3qh8vvgd33czpyrf70tji1guolgwz7tjzmejxxrzbtijzyrgswjdorxy13svzkhhzmtjc12kbtijza2dhwkpiyxlkqgpo3cvorlvcz2a7l3jzd2gm0qyi7x713svzwtjoluu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcrgdmnzpzxxbbyw0onxu13svzj3j1qtycxgdcqb17frko0k0z720qqkwo23gcnldxcgabq3dogrkbyw0on2yqqkwokthknj0318a7qx8o82jbyw0o1xw3quyor3bknydcu2a7q3ypdgg7etfmire3qsyorchontfxmrkbnowoljg7wyvz7jlzqrdpkcf72tfxmgssm80oyrgkwrpii2wctgfptck3nt0318a7qxwoy2vs0rjo7reeqa0ostdqlh8xc2a33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg7wyvz320qqkvzshhbmtpbqgsfqi87frk37k0zvx713svzlcd3ntfxmxffqipolgf77qwii20qqkpoe3hhlg8cvrzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frkowh0o7jlzmg8ia3jsnevc18a7mb0pgrjswtfmirekmsvo0tjhnqpcz2abqb17frkc0rdo880qqkjznhh72tfxmxkumowos2ho0s0onrwctgfpttdqnq0bvgsom787frkowhvm7jlzmgvzecvorlvcz2a7l3jzd2gm0qyi7x713svzwtjoluu3xxfmnc0znrkb0uui3xw1myyzackollvc1gpsmv0zgrfc7tyi32wctgfptchhnl0b18a7m8ypaxfh0qyokx713svzuhd1mu8v18a7q1doggd38uui3gu1qajpn3korlvcu2aznbppm2jc0uui3rebmawp3cvorlvcvxa1qcjomrgm7u0zw2ttqg07ekh3ljjxvrabtijz32h37ujibgl1mju7atjqllvbyxffmodzgggbwtfmire3qkyzy1bkny8cx2afq3yzm2jbyw0oz2wumgyz8cvorlvc72asmi0orxdb0uui3rehqjdpa3kfntfxmrdbq18zfxjbww0ob2wznju7atjblrjb8rzbtijz8xgoetfmirecnuyzekh3lqjxcrkbtijz32h37ujibglkmsjzy1bknypb1gafq28zljg7wudzyxlkqk8z03korlvc82fzqb17frkzwjyi880qqk8patdzmyjxb2fuqi8zt8vs0rpo0re1mju7atj3my8xrrzbtijzsrgfwhdmirecld0oechqll8xxxd33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg7wgdozrlmlgy7atjznh0bvgs7mb0ol2vs0rjo2rwctgfpttdqnq0bvgsom7jzerj38uui3xleqtyz2tdcmewbmrs33czpyxjfwkdmirezmhjzekh3lqjxcrkbtijz32h37ujibglkmsjzy1bkny8c82sbn80oljg70gpig2wznju7atjbmtpbz2dulb17frkowewi1xykmsjz8thqllwbqrjulo8zt8vs0r0or2wbmryzekh3njwb7rahmczpygjm7udo7jlzqkwp7tdzmtpbqrzbtijz12jc0k0o720qqkdzuhhhnhwb0jpsmvdz12j10ldmireuqgypw3k7quu3xxfcmv8zt8vs0r8z7rueqrpot3korlvcqrs1q8ypfrj38uui3retqg8za3f7mtfxmxkfqx0oljg70qvz880qqkwojhdhnhjcprkbl387frk3egpiixyctgfpthfolj8x2gh33czpygj37ypol2wolddzbcvkrl';

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my @llvm_board_option = ();

# On Windows, always use 64-bit binaries.
# On Linux, always use 64-bit binaries, but via the wrapper shell scripts in "bin".
#my $qbindir = ( $^O =~ m/MSWin/ ? 'bin64' : 'bin' );

# For messaging about missing executables
#my $exesuffix = ( $^O =~ m/MSWin/ ? '.exe' : '' );

sub append_to_log { #filename ..., logfile
    my $logfile= pop @_;
    open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
    foreach my $infile (@_) {
      open(TMP, "<$infile")  or mydie("Couldn't open $infile for reading.");
      while(my $l = <TMP>) {
        print LOG $l;
      }
      close TMP;
    }
    close LOG;
}

sub mydie(@) {
    print STDERR "Error: ".join("\n",@_)."\n";
    chdir $orig_dir if defined $orig_dir;
    unlink @cleanup_list unless $save_tmps;
    exit 1;
}

sub myexit(@) {
    print STDERR "Success: ".join("\n",@_)."\n" if $verbose>1;
    chdir $orig_dir if defined $orig_dir;
    unlink @cleanup_list unless $save_tmps;
    exit 0;
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#        'title'  => 'string'     # used mydie and log 
#     }
#   @_[1..$#@_] = arguments of command to execute

sub mysystem_full($@) {
    my $opts = shift(@_);
    my @cmd = @_;

    my $out = $opts->{'stdout'};
    my $title = $opts->{'title'};
    my $err = $opts->{'stderr'};
    my $nodie = $opts->{'nodie'};

    # Log the command to console if requested
    print STDOUT "============ ${title} ============\n" if $title && $verbose>1; 
    if ($verbose >= 2) {
      print join(' ',@cmd)."\n";
    }

    # Replace STDOUT/STDERR as requested.
    # Save the original handles.
    if($out) {
      open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
      open(STDOUT, ">>$out") or mydie "Couldn't redirect STDOUT to $out: $!";
      $| = 1;
    }
    if($err) {
      open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
      open(STDERR, ">>$err") or mydie "Couldn't redirect STDERR to $err: $!";
      select(STDERR);
      $| = 1;
      select(STDOUT);
    }

    # Run the command.
    my $retcode = system(@cmd);

    # Restore STDOUT/STDERR if they were replaced.
    if($out) {
      close(STDOUT) or mydie "Couldn't close STDOUT: $!";
      open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
    }
    if($err) {
      close(STDERR) or mydie "Couldn't close STDERR: $!";
      open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
    }

    if($retcode != 0) {
      my $loginfo = "";
      if($err && $out && ($err != $out)) {
        $loginfo = "\nSee $err and $out for details.";
      } elsif ($err) {
        $loginfo = "\nSee $err for details.";
      } elsif ($out) {
        $loginfo = "\nSee $out for details.";
      }
      if($nodie) {
        print("HLS $title FAILED.$loginfo\n");
      } else {
        mydie("HLS $title FAILED.$loginfo\n");
      }
    }

    return ($retcode >> 8);
}

sub save_pkg_section($$$) {
    my ($pkg,$section,$value) = @_;
    # The temporary file should be in the compiler work directory.
    # The work directory has already been created.
    my $file = $g_work_dir.'/value.txt';
    open(VALUE,">$file") or mydie("Can't write to $file: $!");
    binmode(VALUE);
    print VALUE $value;
    close VALUE;
    $pkg->set_file($section,$file)
      or mydie("Can't save value into package file: $acl::Pkg::error\n");
    unlink $file;
}

sub disassemble ($) {
    my $file=$_[0];
    if ( $disassemble ) {
      mysystem_full({'stdout' => ''}, "llvm-dis ".$file ) == 0 or mydie("Cannot disassemble:".$file."\n"); 
    }
}

sub get_acl_board_hw_path {
    return "$ENV{\"ALTERAOCLSDKROOT\"}/share/models/bm";
}

sub unpack_object_files(@) {
    my $work_dir= shift;
    my @list = ();
    my $file;

    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);

    foreach $file (@_) {
      my $corename = get_name_core($file);
      my $pkg = get acl::Pkg($file);
      if (!$pkg) { #should never trigger
        push @list, $file;
      } else {  
        if ($pkg->exists_section('.hls.fpga.parsed.ll')) {
          my $fname=$work_dir.'/'.$corename.'.fpga.ll';
          $pkg->get_file('.hls.fpga.parsed.ll',$fname);
          push @fpga_IR_list, $fname;
          push @cleanup_list, $fname;
        }
        if ($pkg->exists_section('.hls.tb.parsed.ll')) {
          my $fname=$work_dir.'/'.$corename.'.tb.ll';
          $pkg->get_file('.hls.tb.parsed.ll',$fname);
          push @tb_IR_list, $fname;
          push @cleanup_list, $fname;
        } else {
          # Regular object file 
          push @list, $file;
        } 
      }
    }
    @object_list=@list;

    if (@tb_IR_list + @fpga_IR_list == 0){
      #No need for project directory, remove it
      rmdir $work_dir;
    }
}

sub get_name_core($) {
    my  $base = acl::File::mybasename($_[0]);
    $base =~ s/[^a-z0-9_\.]/_/ig;
    my $suffix = $base;
    $suffix =~ s/.*\.//;
    $base=~ s/\.$suffix//;
    return $base;
}

sub setup_linkstep () {
    # Setup project directory and log file for reminder of compilation
    # We could deduce this from the object files, but that is known at unpacking
    # that requires this to be defined.
    # Only downside of this is if we use a++ to link "real" objects we also reate
    # create an empty project directory
    if (!$project_name) {
        $project_name = 'a';
    }
    $g_work_dir = ${project_name}.'.project';

    # Should remove the project directory to make sure it only contains
    # contents from this compile, probably need to reintroduce functions
    # from aoc to remove recursively, rmdir will not work
    acl::File::make_path($g_work_dir) or mydie($acl::File::error.' While trying to create '.$g_work_dir);
    $project_log=${g_work_dir}.'/'.get_name_core(${project_name}).'.log';
    $project_log = acl::File::abs_path($project_log);
    unlink $project_log;

    # Individual file processing done, populates fpga_IR_list and  tb_IR_list
    unpack_object_files($g_work_dir, @object_list);

}

sub preprocess () {
    my $acl_board_hw_path= get_acl_board_hw_path($board_variant);

    # Make sure the board specification file exists. This is needed by multiple stages of the compile.
    my ($board_spec_xml) = acl::File::simple_glob( $acl_board_hw_path."/$board_variant" );
    my $xml_error_msg = "Cannot find Board specification!\n*** No board specification (*.xml) file inside ".$acl_board_hw_path.". ***\n" ;
    -f $board_spec_xml or mydie( $xml_error_msg );
    push @llvm_board_option, '-board';
    push @llvm_board_option, $board_spec_xml;
}

sub usage() {
    print <<USAGE;

    a++ Compiler for Altera High Level Synthesis (HLS) 

Usage: a++ <options> <kernel>.[cxx|cpp|c] 

Example:
a++ mycomponent.cpp

Outputs:
a.out     Executable result
a.project Contains Quartus component and simulation support

Help Options:
--version
Print out version infomation and exit

-v        
Verbose mode. Report progress of compilation

-h
--help    
Show this message

Overall Options:

-c
Stops after generating verilog. There is currently no way to restart
the compilation from this point.

-o <name>
Renames emulation/simulation executable to <name>, project directory to
<name>.project and verilog file to <name>.v. 

-march=x86-64 
Generate a version of the testbench and components that can execute
locally on the host machine. Generated file is called a.out unless -o is used. 

-march=altera 
Generate a verilog version of the components and a testbench that can 
execute the component in a simulator. Execution/emulation is started by running a.out. This is the default arch if none is given.

--rtl-only
Stop after generating a verilog file.  Only valid for -march=altera.

--cosim
Generate verilog and testbench. Only valid for -march=altera. This is 
default action unless --rtl-only is given.

-g        
Add debug data. Needed by visualizer to view source. Makes it 
possible to symbolically debug kernels created for x86-64
on an x86 machine.

-I <directory> 
Add directory to header search path.

-L <directory> 
Add directory to library search path.

-l<library name> 
Add library to to header search pathlink against.

-D <name> 
Define macro, as name=value or just name.

-W        
Supress warning.

-Werror   
Make all warnings into errors.


Modifiers:
Optimization Control:
--clock <maximum frequency or clock speed>
Instruct the compiler to optimize the circuit for a specific clock frequency.
The clock may be specified in units of GigaHertz, MegaHertz, kiloHertz, Hertz,
seconds, milliseconds, microseconds, nanoseconds, or picoseconds. The default
maximum frequency is 240MHz.

--fp-relaxed
Allow the compiler to relax the order of arithmetic operations,
possibly affecting the precision

--fpc 
Removes intermediary roundings and conversions when possible, 
and changes the rounding mode to round towards zero for 
multiplies and adds

--promote-integers
Mimic g++ integer promotion behaviour at the cost of increased
resource usage. This may be useful for troubleshooting issues
where a program produces different output when compiled with a++ 
vs. other C++ compilers.

Quartus Standalone Compile:
--qii-compile
Creates a Quartus project that instantiates all components in the design
and then runs the Quartus synthesis flow. Resource utilization of all components is 
reported in qii_compile_report.txt.

--qii-vpins
Implement the components' input and output pins as virtual pins in the Quartus project.

--qii-register-ios
Add registers to the input and output pins of the components to
properly capture those paths in Quartus' timing analysis. These registers are
not counted in the generated resource utilization report (qii_compile_report.txt).

--device <device>
Sets the target device used by the Quartus project. This device must be a
valid part number or family description. Valid family descriptions include
"Max 10", "Arria 10", "Cyclone V", and "Stratix V", the descriptions are
interpreted as case insensitive.

--qii-seed <seed>
Sets the seed used by the Quartus compile.

USAGE

}

sub version($) {
    my $outfile = $_[0];
    print $outfile "a++ (TM)\n";
    print $outfile "Altera++ Compiler, 64-Bit C++ based High Level Synthesis\n";
    print $outfile "Version 0.1 Build 182\n";
    print $outfile "Copyright (C) 2015 Altera Corporation\n";
}

sub norm_family_str {
    my $strvar = shift;
    # strip whitespace
    $strvar =~ s/[ \t]//gs;
    # uppercase the string
    $strvar = uc $strvar;
    return $strvar;
}

sub device_get_family {
    my $qii_family_device = shift;
    my $family_from_quartus = `quartus_sh --tcl_eval get_part_info -family $qii_family_device`;
    # strip braces
    $family_from_quartus =~ s/.*\{(.*)\}.*/\1/;
    chomp $family_from_quartus;
    $family_from_quartus = norm_family_str($family_from_quartus);
    return $family_from_quartus;
}

sub translate_device {
    my $qii_dev_family = shift;
    $qii_dev_family = norm_family_str($qii_dev_family);
    my $qii_device = undef;

    if ($qii_dev_family eq "ARRIA10") {
        $qii_device = "10AX115S2F45I2SGES";
    } elsif ($qii_dev_family eq "STRATIXV") {
        $qii_device = "5SGXMA7H2F35C2";
    } elsif ($qii_dev_family eq "CYCLONEV") {
        $qii_device = "5CSXFC6D6F31C8ES";
    } elsif ($qii_dev_family eq "MAX10") {
        $qii_device = "10M50DAF672C7G";
    } else {
        $qii_device = $qii_dev_family;
    }

    return $qii_device;
}

sub parse_family ($){
    my $family=$_[0];

    ### list of supported families
    my $SV_family = "STRATIXV";
    my $CV_family = "CYCLONEV";
    my $A10_family = "ARRIA10";
    my $M10_family = "MAX10";
    
    ### the associated reference boards
    my %family_to_board_map = (
        $SV_family  => 'SV.xml',
        $CV_family  => 'CV.xml',
        $A10_family => 'A10.xml',
        $M10_family => 'M10.xml',
      );

    my $supported_families_str;
    foreach my $key (keys %family_to_board_map) { 
      $supported_families_str .= "\n\"$key\" ";
    }

    my $board = undef;

    # if no family specified, then use Stratix V family default board
    if (!defined $family) {
        $family = $SV_family;
    }
    # Uppercase family string. 
    $family = norm_family_str($family);

    $board = $family_to_board_map{$family};
    
    if (!defined $board) {
        mydie("Unsupported device family: $family. \nSupported device families: $supported_families_str");
    }

    # set a default device if one has not been specified
    if (!defined $qii_device) {
        $qii_device = translate_device($family);
    }

    return ($family,$board);
}

sub save_and_report{
    my $filename = shift;
    my $pkg = create acl::Pkg(${g_work_dir}.'/'.get_name_core(${project_name}).'.aoco');

    # Visualization support
    if ( $debug_symbols ) { # Need dwarf file list for this to work
      my $files = `file-list \"$g_work_dir/$filename\"`;
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
          save_pkg_section($pkg,'.acl.file.'.$index,$file);
          $pkg->add_file('.acl.source.'. $index,$file)
            or mydie("Can't save source into package file: $acl::Pkg::error\n");
          $index = $index + 1;
      }
      save_pkg_section($pkg,'.acl.nfiles',$index);
    }

    # Save Memory Architecture View JSON file 
    my $mav_file = $g_work_dir.'/mav.json';
    if ( -e $mav_file ) {
      $pkg->add_file('.acl.mav.json', $mav_file)
          or mydie("Can't save mav.json into package file: $acl::Pkg::error\n");
      push @cleanup_list, $mav_file;
    }
    # Save Area Report JSON file 
    my $area_file = $g_work_dir.'/area.json';
    if ( -e $area_file ) {
      $pkg->add_file('.acl.area.json', $area_file)
          or mydie("Can't save area.json into package file: $acl::Pkg::error\n");
      push @cleanup_list, $area_file;
    }
    my $area_file_html = $g_work_dir.'/area.html';
    if ( -e $area_file_html ) {
      $pkg->add_file('.acl.area.html', $area_file_html)
          or mydie("Can't save area.html into package file: $acl::Pkg::error\n");
      push @cleanup_list, $area_file_html;
    }
    elsif ( $verbose > 0 ) {
      print STDOUT "Missing area report information. aocl analyze-area will " .
                   "not be able to generate the area report.\n";
    }
    # Get rid of SPV JSON file ince we don't use it 
    my $spv_file = $g_work_dir.'/spv.json';
    if ( -e $spv_file ) {
      push @cleanup_list, $spv_file;
    }

    # Move over the Optimization Report to the log file 
    my $opt_file = $g_work_dir.'/opt.rpt';
    if ( -e $opt_file ) {
      append_to_log( $opt_file, $project_log );
      push @cleanup_list, $opt_file;
    }

    # If estimate >100% of block ram, rerun opt with lmem replication disabled
    # Don't back off like this if DSE is active.
    #DSE driver

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my $design_area = acl::DSE::dse_driver(0, 0); 
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    
    my $report_file = $g_work_dir.'/report.out';
    open LOG, '>'.$report_file;
    printf(LOG "\n".
        "+--------------------------------------------------------------------+\n".
        "; Estimated Resource Usage Summary                                   ;\n".
        "+----------------------------------------+---------------------------+\n".
        "; Resource                               + Usage                     ;\n".
        "+----------------------------------------+---------------------------+\n".
        "; Logic utilization                      ; %4d\%                     ;\n".
        "; Dedicated logic registers              ; %4d\%                     ;\n".
        "; Memory blocks                          ; %4d\%                     ;\n".
        "; DSP blocks                             ; %4d\%                     ;\n".
        "+----------------------------------------+---------------------------;\n", 
        $design_area->{util}, $design_area->{ffs}, $design_area->{rams}, $design_area->{dsps});
    close LOG;
    
    append_to_log ($report_file, $project_log);
    push @cleanup_list, $report_file;
}

sub clk_get_exp {
    my $var = shift;
    my $exp = $var;
    $exp=~ s/[\.0-9 ]*//;
    return $exp;
}

sub clk_get_mant {
    my $var = shift;
    my $mant = $var;
    my $exp = clk_get_exp($mant);
    $mant =~ s/$exp//g;
    return $mant;
} 

sub clk_get_fmax {
    my $clk = shift;
    my $exp = clk_get_exp($clk);
    my $mant = clk_get_mant($clk);

    # default fmax is 240Mhz
    my $fmax = 240*1000000;

    if ($exp =~ /^GHz/) {
        $fmax = 1000000000 * $mant;
    } elsif ($exp =~ /^MHz/) {
        $fmax = 1000000 * $mant;
    } elsif ($exp =~ /^kHz/) {
        $fmax = 1000 * $mant;
    } elsif ($exp =~ /^Hz/) {
        $fmax = $mant;
    } elsif ($exp =~ /^ms/) {
        $fmax = 1000/$mant;
    } elsif ($exp =~ /^us/) {
        $fmax = 1000000/$mant;
    } elsif ($exp =~ /^ns/) {
        $fmax = 1000000000/$mant;
    } elsif ($exp =~ /^ps/) {
        $fmax = 1000000000000/$mant;
    } elsif ($exp =~ /^s/) {
        $fmax = 1/$mant;
    }
 
    $fmax = $fmax/1000000;
    return $fmax;
}

sub parse_args {
    my @user_parseflags = ();
    my @user_linkflags =();

    while ( $#ARGV >= 0 ) {
      my $arg = shift @ARGV;
      if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
      elsif ( ($arg eq '--version') or ($arg eq '-V') ) { version(\*STDOUT); exit 0; }
      elsif ( ($arg eq '-v') ) { $verbose += 1; if ($verbose > 1) {$prog = "#$prog";} }
      elsif ( ($arg eq '-g') ) { $debug_symbols = 1;}
      elsif ( ($arg eq '-o') ) {
          # Absorb -o argument, and don't pass it down to Clang
          $#ARGV >= 0 or mydie("Option $arg requires a name argument.");
          $project_name = shift @ARGV;
      }
      elsif ($arg eq '-march=emulator' || $arg eq '-march=x86-64') {
          $emulator_flow = 1;
      }
      elsif ($arg eq '-march=simulator' || $arg eq '-march=altera') {
          $simulator_flow = 1;
      }
      elsif ($arg eq '--RTL-only' || $arg eq '--rtl-only' ) {
          $RTL_only_flow_modifier = 1;
      }
      elsif ($arg eq '--cosim' ) {
          $RTL_only_flow_modifier = 0;
      }
      elsif ($arg eq '--cosim-debug') {
          $RTL_only_flow_modifier = 0;
          $cosim_debug = 1;
      }
      elsif ( ($arg eq '--clang-arg') ) {
          $#ARGV >= 0 or mydie('Option --clang-arg requires an argument');
          # Just push onto args list
          push @user_parseflags, shift @ARGV;
      }
      elsif ( ($arg eq '--opt-arg') ) {
          $#ARGV >= 0 or mydie('Option --opt-arg requires an argument');
          push @additional_opt_args, shift @ARGV;
      }
      elsif ( ($arg eq '--llc-arg') ) {
          $#ARGV >= 0 or mydie('Option --llc-arg requires an argument');
          push @additional_llc_args, shift @ARGV;
      }
      elsif ( ($arg eq '--optllc-arg') ) {
          $#ARGV >= 0 or mydie('Option --optllc-arg requires an argument');
          my $optllc_arg = (shift @ARGV);
          push @additional_opt_args, $optllc_arg;
          push @additional_llc_args, $optllc_arg;
      }
      elsif ( ($arg eq '--sysinteg-arg') ) {
          $#ARGV >= 0 or mydie('Option --sysinteg-arg requires an argument');
          push @additional_sysinteg_args, shift @ARGV;
      }
      elsif ( ($arg eq '--v-only') ) { $verilog_gen_only = 1; }

      elsif ( ($arg eq '-c') ) { $object_only_flow_modifier = 1; }

      elsif ( ($arg eq '--dis') ) { $disassemble = 1; }   
      elsif ($arg eq '--family') {
          ($family_legacy) = (shift @ARGV);
      } 
      elsif ($arg eq '--dot') {
          $dotfiles = 1;
      }
      elsif ($arg eq '--save-temps') {
          $save_tmps = 1;
      }
      elsif ( ($arg eq '--fmax') ) {
          if ($qii_fmax_constraint != 0) {
               mydie("The --fmax argument is deprecated, please use --clock\n");
          } 
          print("The --fmax argument is deprecated, please update your tests to use --clock\n");
          $qii_fmax_constraint = (shift @ARGV);
          push @additional_opt_args, '-scheduler-fmax='.$qii_fmax_constraint;
          push @additional_llc_args, '-scheduler-fmax='.$qii_fmax_constraint;
      }
      elsif ( ($arg eq '--clock') ) {
          if ($qii_fmax_constraint != 0) {
               mydie("The --fmax argument is deprecated, please use --clock\n");
          } 
          my $clk_option = (shift @ARGV);
          $qii_fmax_constraint = clk_get_fmax($clk_option);
          push @additional_opt_args, '-scheduler-fmax='.$qii_fmax_constraint;
          push @additional_llc_args, '-scheduler-fmax='.$qii_fmax_constraint;
      }
      elsif ( ($arg eq '--fp-relaxed') ) {
          push @additional_opt_args, "-fp-relaxed=true";
      }
      elsif ( ($arg eq '--fpc') ) {
          push @additional_opt_args, "-fpc=true";
      }
      elsif ( ($arg eq '--promote-integers') ) {
          push @user_parseflags, "-fhls-int-promotion";
      }
      # Soft IP C generation flow
      elsif ($arg eq '--soft-ip-c') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $disassemble = 1;
      }
      # Soft IP C generation flow for x86
      elsif ($arg eq '--soft-ip-c-x86') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $target_x86 = 1;
          $opt_passes = "-inline -inline-threshold=10000000 -dce -stripnk -cleanup-soft-ip";
          $disassemble = 1;
      }
      elsif ($arg eq '--qii-compile') {
          $qii_flow = 1;
      }
      elsif ($arg eq '--qii-vpins') {
          $qii_vpins = 1;
      }
      elsif ($arg eq '--qii-register-ios') {
          $qii_io_regs = 1;
      }
      elsif ($arg eq "--qii-device") {
          $qii_device_legacy = shift @ARGV;
      }
      elsif ($arg eq "--device") {
          $qii_device = shift @ARGV;
          $qii_device = translate_device($qii_device);
          $family = device_get_family($qii_device); 
          if ($family eq "") {
               mydie("Device $qii_device is not known, please specify a known device\n");
          }
      }
      elsif ($arg eq "--qii-seed") {
          $qii_seed = shift @ARGV;
      }
      elsif ($arg =~ /^-[lL]/ or
             $arg =~ /^-Wl/) { 
          push @user_linkflags, $arg;
      }
      elsif ($arg =~ /^-I /) { # -Iinc syntax falls through to default below
          $#ARGV >= 0 or mydie("Option $arg requires a name argument.");
          push  @user_parseflags, $arg.(shift @ARGV);
      }
      elsif ( $arg =~ m/\.c$|\.cc$|\.cp$|\.cxx$|\.cpp$|\.CPP$|\.c\+\+$|\.C$/ ) {
          push @source_list, $arg;
      }
      elsif ( $arg =~ m/\.o$/ ) {
          push @object_list, $arg;
      } else { push @user_parseflags, $arg }
    }

    if ((defined $qii_device_legacy) && (defined $qii_device)) {
        mydie("The --qii-device is deprecated, please use only the --device option\n");
    }

    if ((defined $qii_device_legacy) && (defined $family_legacy)) {
        print "The --qii-device and --family options are deprecated, please use only the --device option\n";
    }

    if ((defined $family_legacy) && (defined $qii_device)) {
        mydie("The --family argument is deprecated, please use only --device option\n");
    }

    if ((defined $qii_device_legacy) && (!defined $qii_device)) {
        print "The --qii-device is deprecated, please use the --device option\n";
        $qii_device = $qii_device_legacy;
    }

    if ((defined $family_legacy) && (!defined $family) && (!defined $qii_device)) {
        print "The --family argument is deprecated, please use only --device option\n";
        $family = $family_legacy;
    }

    # All arguments in, make sure we have at least one file
    (@source_list + @object_list) > 0 or mydie('No input files');
    if ($debug_symbols) {
      push @user_parseflags, '-g';
      push @additional_llc_args, '-dbg-info-enabled';
    } 

    # Make sure that the qii compile flow is only used with the altera compile flow
    if ($qii_flow and not $simulator_flow) {
        mydie("The --qii-compile argument can only be used with -march=altera\n");
    }

    ($family, $board_variant) = parse_family($family);

    if ($dotfiles) {
      push @additional_opt_args, '--dump-dot';
      push @additional_llc_args, '--dump-dot'; 
      push @additional_sysinteg_args, '--dump-dot';
    }

    # caching is disabled for LSUs in HLS components for now
    # enabling caches is tracked by case:314272
    push @additional_opt_args, '-nocaching';
    push @additional_opt_args, '-noprefetching';

    $orig_dir = acl::File::abs_path('.');

    if ( $project_name ) {
      if ( $#source_list > 0 && $object_only_flow_modifier) {
        mydie("Cannot specify -o with -c and multiple soure files\n");
      }
    }
    

    # Check that this is a valid board directory by checking for a board model .xml 
    # file in the board directory.
    if (not $emulator_flow) {
      my $board_xml = get_acl_board_hw_path($board_variant).'/'.$board_variant;
      if (!-f $board_xml) {
        mydie("Board '$board_variant' not found!\n");
      }
    }
    # Consolidate some flags
    push (@parseflags, @user_parseflags);
    push (@parseflags,"-I$ENV{\"ALTERAOCLSDKROOT\"}/include");
    push (@parseflags,"-I$ENV{\"ALTERAOCLSDKROOT\"}/host/include");
    
    my $emulator_arch=acl::Env::get_arch();
    my $host_lib_path = acl::File::abs_path( acl::Env::sdk_root().'/host/'.${emulator_arch}.'/lib');
    push (@linkflags, @user_linkflags);
    push (@linkflags, '-lstdc++');
    push (@linkflags, '-L'.$host_lib_path);
}

sub fpga_parse ($$){  
    my $source_file= shift;
    my $objfile = shift;
    $pkg = undef;

    # OK, no turning back remove the result file, so no one thinks we succedded
    unlink $objfile;
    if (!$object_only_flow_modifier) { push @cleanup_list, $objfile; };

    $pkg = create acl::Pkg($objfile);
    push @object_list, $objfile;

    my $work_dir=$objfile.'.'.$$.'.tmp';
    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);

    my $outputfile=$work_dir.'/fpga.ll';

    my @clang_std_opts2 = qw(-S -x hls -emit-llvm -DALTERA_CL -Wuninitialized -fno-exceptions);
    if ( $target_x86 == 0 ) { push (@clang_std_opts2, qw(-ccc-host-triple fpga64-unknown-linux)); }

    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts2,
      "-D__ALTERA_TYPE__=$macro_type_string",
      "-D__ALTERA_FMAX__=$qii_fmax_constraint",
      @parseflags,
      $source_file,
      '-o', $outputfile);

    $return_status = mysystem_full( {'title' => 'fpga Parse'}, @cmd_list);

    # add 
    $pkg->add_file('.hls.fpga.parsed.ll',$outputfile);
    unlink $outputfile unless $save_tmps;
}

sub testbench_parse ($$) {
    my $source_file= shift;
    my $object_file = shift;

    my $work_dir=$object_file.'.'.$$.'.tmp';
    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);

    #Temporarily disabling exception handling here, Tracking in FB223872
    my @clang_std_opts = qw(-S -emit-llvm  -x hls -O0 -DALTERA_CL -Wuninitialized -fno-exceptions);

    my @macro_options;
    @macro_options= qw(-DHLS_COSIMULATION -Dmain=__altera_hls_main);

    my $outputfile=$work_dir.'/tb.ll';
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts,
      "-D__ALTERA_TYPE__=$macro_type_string",
      "-D__ALTERA_FMAX__=$qii_fmax_constraint",
      @parseflags,
      @macro_options,
      $source_file,
      '-o', $outputfile,
      );

    mysystem_full( {'title' => 'Sim Testbench Parse'}, @cmd_list);

    $pkg->add_file('.hls.tb.parsed.ll',$outputfile);
    # We are done, cleanup
    unlink $outputfile unless $save_tmps;
    rmdir $work_dir unless $save_tmps;
}

sub emulator_compile ($$) {
    my $source_file= shift;
    my $object_file = shift;
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      qw(-x hls -O0 -DALTERA_CL -Wuninitialized -c),
      '-DHLS_EMULATION',
      "-D__ALTERA_TYPE__=$macro_type_string",
      "-D__ALTERA_FMAX__=$qii_fmax_constraint",
      $source_file,
      @parseflags,
      '-o',$object_file
      );
    
    mysystem_full(
      {'title' => 'Emulator compile'}, @cmd_list);
    
    push @object_list, $object_file;
    if (!$object_only_flow_modifier) { push @cleanup_list, $object_file; };
}

sub generate_testbench(@) {
    my ($IRfile)=@_;
    my $resfile=$g_work_dir.'/tb.bc';
    my @flow_options= qw(-replacecomponentshlssim);
    
    @cmd_list = (
      $opt_exe,  
      @flow_options,
      @additional_opt_args,
      @llvm_board_option,
      '-o', $resfile,
      $g_work_dir.'/'.$IRfile );

    mysystem_full( {'title' => 'opt (host tweaks))'}, @cmd_list);

    disassemble($resfile);
    
    @cmd_list = (
      $clang_exe,
      qw(-B/usr/bin -fPIC -shared -O0),
      $g_work_dir.'/tb.bc',
      "-D__ALTERA_TYPE__=$macro_type_string",
      "-D__ALTERA_FMAX__=$qii_fmax_constraint",
      @object_list,
      '-Wl,-soname,a_sim.so',
      '-o', $g_work_dir.'/a_sim.so',
      @linkflags, qw(-lhls_cosim) );

    mysystem_full({'title' => 'clang (executable testbench image)'}, @cmd_list );

    # we used the regular objects, remove them so we don't think this is emulation
    @object_list=();
}

sub generate_fpga(@){
    my @IR_list=@_;
    my $linked_bc=$g_work_dir.'/fpga.linked.bc';
    
    # initializes DSE, used for area estimates
    acl::DSE::dse_prologue($g_work_dir);

    # Link with standard library.
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_early.bc');
    @cmd_list = (
      $link_exe,
      @IR_list,
      $early_bc,
      '-o',
      $linked_bc );
    
    $return_status = mysystem_full( {'title' => 'Early Link'}, @cmd_list);
    
    disassemble($linked_bc);
    
    # llc produces visualization data in the current directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    my $kwgid='fpga.opt.bc';
    my @flow_options = qw(-HLS);
    if ( $soft_ip_c_flow_modifier ) { push(@flow_options, qw(-SIPC)); }
    my @cmd_list = (
      $opt_exe,
      @flow_options,
      split( /\s+/,$opt_passes),
      @llvm_board_option,
      @additional_opt_args,
      'fpga.linked.bc',
      '-o', $kwgid );
    
    $return_status = mysystem_full( {'title' => 'Main Opt pass'}, @cmd_list );
    
    disassemble($kwgid);
    
    if ( $soft_ip_c_flow_modifier ) { myexit('Opt Step'); }

    my $lowered='fpga.lowered.bc';
    # Lower instructions to IP library function calls
    
    @cmd_list = (
      $opt_exe,
      qw(-HLS -insert-ip-library-calls),
      @additional_opt_args,
      $kwgid,
      '-o', $lowered);

    $return_status = mysystem_full( {'title' => 'Lower to IP'}, @cmd_list );

    my $linked='fpga.linked2.bc';
    # Link with the soft IP library 
    my $late_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_late.bc');
    @cmd_list = (
      $link_exe,
      $lowered,
      $late_bc,
      '-o', $linked );

    $return_status = mysystem_full( {'title' => 'Late library'}, @cmd_list);

    my $final = get_name_core(${project_name}).'.bc';
    # Inline IP calls, simplify and clean up
    @cmd_list = (
      $opt_exe,
      qw(-HLS -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -area-print),
      @llvm_board_option,
      @additional_opt_args,
      $linked,
      '-o', $final);

    $return_status = mysystem_full( {'title' => 'Inline and clean up'}, @cmd_list);

    disassemble($final);

    @cmd_list = (
      $llc_exe,
      qw( -march=fpga -mattr=option3wrapper -fpga-const-cache=1 -HLS),
      qw(--board hls.xml),
      @additional_llc_args,
      $final,
      '-ifacefromfile',
      '-o',
      get_name_core($project_name).'.v' );

    $return_status = mysystem_full({'title' => 'LLC'}, @cmd_list);


    my $xml_file = get_name_core(${project_name}).'.bc.xml';

    mysystem_full(
      {'title' => 'System Integration'},
      ($sysinteg_exe, @additional_sysinteg_args,'--hls', 'hls.xml', $xml_file ));


    my @components = get_generated_components();
    my $ipgen_result = create_qsys_components(@components);
    mydie("Failed to generate QIP files\n") if ($ipgen_result);

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    #Cleanup everything but final bc
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.*.bc" );
    push @cleanup_list, $g_work_dir.'interfacedesc.txt';

    save_and_report(${final});
}

sub link_IR (@) {
    my ($resfile,@list) = @_;
    my $full_name = ${g_work_dir}.'/'.${resfile};
    # Link with standard library.
    @cmd_list = (
      $link_exe,
      @list,
      '-o',$full_name );

    $return_status = mysystem_full( {'title' => 'Link IR'}, @cmd_list);

    disassemble($full_name);
}

sub link_x86 ($) {
    my $output_name = shift ;

    @cmd_list = (
      $clang_exe,
      "-D__ALTERA_TYPE__=$macro_type_string",
      "-D__ALTERA_FMAX__=$qii_fmax_constraint",
      @object_list,
      '-o',
      $executable,
      @linkflags,
      '-lhls_emul'
      );
    
    mysystem_full( {'title' => 'Emulator Link'}, @cmd_list);

    return;
}

sub get_generated_components() {

    # read the comma-separated list of components from a file
    my $COMPONENT_LIST_FILE;
    open (COMPONENT_LIST_FILE, "<interfacedesc.txt") or mydie "Couldn't open interfacedesc.txt for read!\n";
    my @dut_array;
    while(my $var =<COMPONENT_LIST_FILE>) {
      push(@dut_array,($var =~ /^(\S+)/)); 
    }
    close COMPONENT_LIST_FILE;

    return @dut_array;
}

sub hls_sim_generate_verilog($) {
    my ($HLS_FILENAME_NOEXT) = $_;
    if (!$HLS_FILENAME_NOEXT) {
      $HLS_FILENAME_NOEXT='a';
    }

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");

    my @dut_array = get_generated_components();
    # finally, recreate the comma-separated string from the array with unique elements
    my $DUT_LIST  = join(',',@dut_array);

    print "Generating simulation files for components: $DUT_LIST in $HLS_FILENAME_NOEXT\n" if $verbose;

    if (!defined($HLS_FILENAME_NOEXT) or !defined($DUT_LIST)) {
      mydie("Error: Pass the input file name and component names into the hls_sim_generate_verilog function\n");
    }

    my $HLS_GEN_FILES_DIR = $HLS_FILENAME_NOEXT;
    my $SEARCH_PATH = acl::Env::sdk_root()."/ip/,.,\$"; # no space between paths!

    # Setup file path names
    my $HLS_GEN_FILES_SIM_DIR = './sim';
    my $HLS_QSYS_SIM_NOEXT    = $HLS_FILENAME_NOEXT.'_sim';

    # Because the qsys-script tcl cannot accept arguments, 
    # pass them in using the --cmd option, which runs a tcl cmd
    my $init_var_tcl_cmd = "set sim_qsys $HLS_FILENAME_NOEXT; set component_list $DUT_LIST;";

    # Create the simulation directory  
    my $sim_dir_abs_path = acl::File::abs_path("./$HLS_GEN_FILES_SIM_DIR");
    print "HLS simulation directory: $sim_dir_abs_path.\n" if $verbose;
    acl::File::make_path($HLS_GEN_FILES_SIM_DIR) or mydie("Can't create simulation directory $sim_dir_abs_path: $!");

    my $gen_qsys_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_sim_generate_qsys.tcl";

    # Run hls_sim_generate_qsys.tcl to generate the .qsys file for the simulation system 
    $return_status = mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log, 'title' => 'gen_qsys'},
      'qsys-script --search-path='.$SEARCH_PATH.' --script='.$gen_qsys_tcl.' --cmd="'.$init_var_tcl_cmd.'"');

    # Move the .qsys we just made to the sim dir
    $return_status = mysystem_full({'stdout' => $project_log, , 'stderr' => $project_log, 'title' => 'move qsys'},"mv $HLS_QSYS_SIM_NOEXT.qsys $HLS_GEN_FILES_SIM_DIR");

    # Generate the verilog for the simulation system
    @cmd_list = ('qsys-generate',
      '--search-path='.$SEARCH_PATH,
      '--simulation=VERILOG',
      '--output-directory='.$HLS_GEN_FILES_SIM_DIR,
      '--family='.$family,
      '--part='.$qii_device,
      "$HLS_GEN_FILES_SIM_DIR/$HLS_QSYS_SIM_NOEXT.qsys");

    $return_status = mysystem_full(
      {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate verilog'}, 
      @cmd_list);

    # Generate simulation scripts
    @cmd_list = ('ip-make-simscript',
      '--compile-to-work',
      "-spd=$HLS_GEN_FILES_SIM_DIR/$HLS_QSYS_SIM_NOEXT.spd",
      "--output-directory=$HLS_GEN_FILES_SIM_DIR");
    
    $return_status = mysystem_full(
      {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate simulation script'},
      @cmd_list);

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    # Generate scripts that the user can run to perform the actual simulation.
    my $qsys_dir = get_qsys_output_dir("SIM_VERILOG");
    generate_simulation_scripts($HLS_FILENAME_NOEXT, "sim/$qsys_dir", $g_work_dir);
}


# This module creates a file:
# Moved everything into one file to deal with run time parameters, i.e. execution directory vs scripts placement.
#Previous do scripts are rewritten to strings that gets put into the run script
#Also perl driver in project directory is gone.
#  - compile_do      (the string run by the compilation phase, in the output dir)
#  - simulate_do     (the string run by the simulation phase, in the output dir)
#  - <source>        (the executable top-level simulation script, in the top-level dir)
sub generate_simulation_scripts($) {
    my ($HLS_QSYS_SIM_NOEXT, $HLS_GEN_FILES_SIM_DIR, $g_work_dir) = @_;

    # Working directories
    my $projdir = acl::File::mybasename($g_work_dir);
    my $outputdir = acl::File::mydirname($g_work_dir);
    my $simscriptdir = "$HLS_GEN_FILES_SIM_DIR/mentor";
    # Script filenames
    my $fname_compilescript = "$simscriptdir/msim_compile.tcl";
    my $fname_runscript = "$simscriptdir/msim_run.tcl";
    my $fname_msimsetup = "$simscriptdir/msim_setup.tcl";
    my $fname_svlib = "$HLS_QSYS_SIM_NOEXT"."_sim";
    my $fname_msimini = "modelsim.ini";
    my $fname_exe_com_script = "compile.sh";

    # Other variables
    my $top_module = "$HLS_QSYS_SIM_NOEXT"."_sim";

    # Generate the modelsim compilation script
    my $COMPILE_SCRIPT_FILE;
    open(COMPILE_SCRIPT_FILE, ">", "$g_work_dir/$fname_compilescript") or mydie "Couldn't open $g_work_dir/$fname_compilescript for write!\n";
    print COMPILE_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print COMPILE_SCRIPT_FILE "set QSYS_SIMDIR \${scripthome}/$projdir/$simscriptdir/..\n";
    print COMPILE_SCRIPT_FILE "source \${scripthome}/$projdir/$fname_msimsetup\n";
    print COMPILE_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib \${scripthome}/$projdir/$fname_svlib";
    print COMPILE_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                            : "\"\n");
    print COMPILE_SCRIPT_FILE "dev_com\n";
    print COMPILE_SCRIPT_FILE "com\n";
    print COMPILE_SCRIPT_FILE "elab\n";
    print COMPILE_SCRIPT_FILE "exit -code 0\n";
    close(COMPILE_SCRIPT_FILE);

    # Generate the run script
    my $RUN_SCRIPT_FILE;
    open(RUN_SCRIPT_FILE, ">", "$g_work_dir/$fname_runscript") or mydie "Couldn't open $g_work_dir/$fname_runscript for write!\n";
    print RUN_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print RUN_SCRIPT_FILE "set QSYS_SIMDIR \${scripthome}/$projdir/$simscriptdir/..\n";
    print RUN_SCRIPT_FILE "source \${scripthome}/$projdir/$fname_msimsetup\n";
    print RUN_SCRIPT_FILE "# Suppress warnings from the std arithmetic libraries\n";
    print RUN_SCRIPT_FILE "set StdArithNoWarnings 1\n";
    print RUN_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib \${scripthome}/$projdir/$fname_svlib";
    print RUN_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                        : "\"\n");
    print RUN_SCRIPT_FILE "elab\n";
    print RUN_SCRIPT_FILE "log -r *\n" if $cosim_debug;
    print RUN_SCRIPT_FILE "run -all\n";
    print RUN_SCRIPT_FILE "exit -code 0\n";
    close(RUN_SCRIPT_FILE);

    # Generate the executable script
    my $EXE_FILE;
    open(EXE_FILE, '>', $executable) or die "Could not open file '$executable' $!";
    print EXE_FILE "#!/bin/sh\n";
    print EXE_FILE "\n";
    print EXE_FILE "# Identify the directory to run from\n";
    print EXE_FILE "scripthome=\$(dirname \$0)\n";
    print EXE_FILE "# Run the testbench\n";
    print EXE_FILE "vsim -batch -modelsimini \${scripthome}/$projdir/$fname_msimini -nostdout -keepstdout -l transcript.log -stats=none -do \"set scripthome \${scripthome}; do \${scripthome}/$projdir/$fname_runscript\"\n";
    print EXE_FILE "if [ \$? -ne 0 ]; then\n";
    print EXE_FILE "  >&2 echo \"ModelSim simulation failed.  See transcript.log for more information.\"\n";
    print EXE_FILE "  exit 1\n";
    print EXE_FILE "fi\n";
    print EXE_FILE "exit 0\n";
    close(EXE_FILE);
    system("chmod +x $executable"); 

    # Generate a script that we'll call to compile the design
    my $EXE_COM_FILE;
    open(EXE_COM_FILE, '>', "$g_work_dir/$fname_exe_com_script") or die "Could not open file '$g_work_dir/$fname_exe_com_script' $!";
    print EXE_COM_FILE "#!/bin/sh\n";
    print EXE_COM_FILE "\n";
    print EXE_COM_FILE "# Identify the directory to run from\n";
    print EXE_COM_FILE "scripthome=\$(dirname \$0)/..\n";
    print EXE_COM_FILE "# Compile and elaborate the testbench\n";
    print EXE_COM_FILE "vsim -batch -modelsimini \${scripthome}/$projdir/$fname_msimini -do \"set scripthome \${scripthome}; do \${scripthome}/$projdir/$fname_compilescript\"\n";
    print EXE_COM_FILE "exit \$?\n";
    close(EXE_COM_FILE);
    system("chmod +x $g_work_dir/$fname_exe_com_script"); 

    # Modelsim maps its libraries to ./libraries - to keep paths consistent we'd like to map them to
    # scripthome/g_work_dir/libraries
    my $MSIM_SETUP_FILE;
    open(MSIM_SETUP_FILE, "<", "$g_work_dir/$fname_msimsetup") || die "Could not open $g_work_dir/$fname_msimsetup for read.";
    my @lines = <MSIM_SETUP_FILE>;
    close(MSIM_SETUP_FILE);
    foreach(@lines) {
      s^\./libraries/^\${scripthome}/$projdir/libraries/^g;
    }
    open(MSIM_SETUP_FILE, ">", "$g_work_dir/$fname_msimsetup") || die "Could not open $g_work_dir/$fname_msimsetup for write.";
    print MSIM_SETUP_FILE @lines;
    close(MSIM_SETUP_FILE);

    # Generate the common modelsim.ini file
    @cmd_list = ('vmap','-c');
    $return_status = mysystem_full({'stdout' => $project_log,'stderr' => $project_log,
                                    'title' => 'Capture default modelsim.ini'}, 
                                    @cmd_list);
    acl::File::copy('modelsim.ini', "$g_work_dir/$fname_msimini");
    acl::File::remove_tree('modelsim.ini');

    # Compile the cosim design
=begin comment
    @cmd_list = ('vsim',
      "-batch",
      "-modelsimini",
      "$g_work_dir/$fname_msimini",
      "-do",
      "set scripthome $outputdir; do $g_work_dir/$fname_compilescript");
=cut
    @cmd_list = ("$g_work_dir/$fname_exe_com_script");
    $return_status = mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log,'nodie' => '1',
       'title' => 'Elaborate cosim testbench.'},
      @cmd_list);
    # Missing license is such a common problem, let's give a special message
    if($return_status == 4) {
      mydie("Missing simulator license.  Either:\n" .
            "  1) Ensure you have a valid ModelSim license\n" .
            "  2) Use the --rtl-only flag to skip the cosim flow\n");
    } elsif($return_status != 0) {
      mydie("Cosim testbench elaboration failed.\n");
    }
}

sub gen_qsys_script(@) {
    my @components = @_;


    foreach (@components) {
        # Generate the tcl for the system
        open(my $qsys_script, '>', "$_.tcl") or die "Could not open file '$_.tcl' $!";

        print $qsys_script <<SCRIPT;
package require -exact qsys 15.0

# create the system with the name

create_system $_

# set project properties

set_project_property HIDE_FROM_IP_CATALOG false
set_project_property DEVICE_FAMILY "${family}"
set_project_property DEVICE "${qii_device}"

# adding the ip for which the variation has to be created for

add_instance ${_}_internal_inst ${_}_internal

# auto export all the interfaces

# this will make the exported ports to have the same port names as that of altera_pcie_a10_hip

set_instance_property ${_}_internal_inst AUTO_EXPORT true

# save the Qsys file

save_system "$_.qsys"
SCRIPT
        close $qsys_script;
    }

}

sub run_qsys_script(@) {
    my @components = @_;

    my $return_status = 0;

    foreach (@components) {
        # Generate the verilog for the simulation system
        @cmd_list = ('qsys-script',
                "--script=$_.tcl");

        $return_status |= mysystem_full(
            {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate component QSYS script'}, 
            @cmd_list);
    }

    return $return_status;
}

sub post_process_qsys_files(@) {
    my @components = @_;

    my $return_status = 0;

    foreach (@components) {

	# Read in the current QSYS file
        open (FILE, "<${_}.qsys") or die "Can't open ${_}.qsys for read";
	my @lines;
        while (my $line = <FILE>) {
		# this organizes the components in the IP catalog under the same HLS/ directory
		$line =~ s/categories=""/categories="HLS"/g;
		push(@lines, $line);
	}
        close(FILE);

	# Write out the modified QSYS file
    	open (OFH, ">${_}.qsys") or die "Can't open ${_}.qsys for write";
	foreach my $line (@lines) {
		print OFH $line;
	}
    	close(OFH);

    }

    return $return_status;
}

sub run_qsys_generate($@) {
    my ($target, @components) = @_;

    my $return_status = 0;

    foreach (@components) {
        # Generate the verilog for the simulation system
        @cmd_list = ('qsys-generate',
                "--$target=VERILOG",
                "--family=$family",
      	        '--part='.$qii_device,
                $_ . ".qsys");

        $return_status |= mysystem_full(
            {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate verilog and qip for QII compile'}, 
            @cmd_list);
    }

    return $return_status;
}

sub create_qsys_components(@) {
    my @components = @_;

    gen_qsys_script(@components);
    run_qsys_script(@components);
    post_process_qsys_files(@components);
    run_qsys_generate("synthesis", @components);
}

sub get_qsys_output_dir($) {
   my ($target) = @_;

   my $dir = ($target eq "SIM_VERILOG") ? "simulation" : "synthesis";

   if ($family eq "ARRIA10") {
      $dir = ($target eq "SIM_VERILOG")   ? "sim"   :
             ($target eq "SYNTH_VERILOG") ? "synth" :
                                            "";
   }

   return $dir;
}

sub generate_top_level_qii_verilog($@) {
    my ($qii_project_name, @components) = @_;

    my $clock2x_used = 0;
    my %component_portlists;

    my $qsys_dir = get_qsys_output_dir("SYNTH_VERILOG");

    foreach (@components) {
            #read in component module from file and parse for portlist
            open (FILE, "<../${_}/${qsys_dir}/${_}.v") or die "Can't open ../${_}/${qsys_dir}/${_}.v for read";

            #parse for portlist
            my $in_module = 0;
            while (my $line = <FILE>) {
                if ($in_module) {
                    #this regex only picks up legal verilog identifiers, not escaped identifiers
                    if ($line =~ m/^\s*(input|output)\s+wire\s+(\[\d+:\d+\])?\s*([a-zA-Z_0-9\$]+),?\s*/) {
                        push(@{$component_portlists{$_}}, {'dir' => $1, 'range' => $2, 'name' => $3});
                        if ($3 eq "clock2x") {
                            $clock2x_used = 1;
                        }
                    } elsif ($line =~ m/^\s*(input|output)\s+([a-zA-Z_0-9\$]+)\s+([a-zA-Z_0-9\$]+),?\s*/){
                        # handle structs
                        push(@{$component_portlists{$_}}, {'dir' => $1, 'range' => "[\$bits($2)-1:0]", 'name' => $3});
                    } elsif ($line =~ m/\s*endmodule\s*/){
                        $in_module = 0;
                    }
                } elsif (not $in_module and ($line =~ m/^\s*module\s+${_}\s/)) {
                    $in_module = 1;
                }
            }

            close(FILE);
    }

    #output top level
    open (OFH, ">${qii_project_name}.v") or die "Can't open ${qii_project_name}.v for write";
    print OFH "module ${qii_project_name} (\n";

    #ports
    print OFH "\t  input logic resetn\n";
    print OFH "\t, input logic clock\n";
    if ($clock2x_used) {
        print OFH "\t, input logic clock2x\n";
    }
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};
        foreach my $port (@portlist) {

            #skip clocks and reset
            my $port_name = $port->{'name'};
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }

            #component ports
            print OFH "\t, $port->{'dir'} logic $port->{'range'} ${_}_$port->{'name'}\n";
        }
    }
    print OFH "\t);\n\n";

    if ($qii_io_regs) {
        #declare registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};
            foreach my $port (@portlist) {
                my $port_name = $port->{'name'};

                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }

                print OFH "\tlogic $port->{'range'} ${_}_${port_name}_reg;\n";
            }
        }

        #wire registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};

            print OFH "\n\n\talways @(posedge clock) begin\n";
            foreach my $port (@portlist) {
                my $port_name = "$port->{'name'}";

                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }

                $port_name = "${_}_${port_name}";
                if ($port->{'dir'} eq "input") {
                    print OFH "\t\t${port_name}_reg <= ${port_name};\n";
                } else {
                    print OFH "\t\t${port_name} <= ${port_name}_reg;\n";
                }
            }
            print OFH "\tend\n";
        }
    }

    #component instances
    my $comp_idx = 0;
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};

        print OFH "\n\n\t${_} hls_component_dut_inst_${comp_idx} (\n";
        print OFH "\t\t  .resetn(resetn)\n";
        print OFH "\t\t, .clock(clock)\n";
        if ($clock2x_used) {
            print OFH "\t\t, .clock2x(clock2x)\n";
        }

        foreach my $port (@portlist) {

            my $port_name = $port->{'name'};

            #skip clocks and reset
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }

            my $reg_name_suffix = $qii_io_regs ? "_reg" : "";
            my $reg_name = "${_}_${port_name}${reg_name_suffix}";
            print OFH "\t\t, .${port_name}(${reg_name})\n";
        }
        print OFH "\t);\n\n";
        $comp_idx = $comp_idx + 1
    }

    print OFH "\n\nendmodule\n";
    close(OFH);

    return $clock2x_used;

}

sub generate_qsf($@) {
    my ($qii_project_name, @components) = @_;

    open (OUT_QSF, ">${qii_project_name}.qsf") or die;

    print OUT_QSF "set_global_assignment -name FAMILY \\\"${family}\\\"\n";
    print OUT_QSF "set_global_assignment -name DEVICE ${qii_device}\n";
    print OUT_QSF "set_global_assignment -name TOP_LEVEL_ENTITY ${qii_project_name}\n";
    print OUT_QSF "set_global_assignment -name SDC_FILE ${qii_project_name}.sdc\n";

    if ($qii_vpins) {
        my $qii_vpin_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_create_vpins.tcl";
        print OUT_QSF "set_global_assignment -name POST_MODULE_SCRIPT_FILE \\\"quartus_sh:${qii_vpin_tcl}\\\"\n";
    }

    # add call to parsing script after STA is run
    my $qii_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_report.tcl";
    print OUT_QSF "set_global_assignment -name POST_FLOW_SCRIPT_FILE \\\"quartus_sh:${qii_rpt_tcl}\\\"\n";

    # add component QIP files to project
    my $qsys_dir = get_qsys_output_dir("QIP");
    foreach (@components) {
        print OUT_QSF "set_global_assignment -name QIP_FILE ../$_/${qsys_dir}/$_.qip\n";
    }

    # add generated top level verilog file to project
    print OUT_QSF "set_global_assignment -name SYSTEMVERILOG_FILE ${qii_project_name}.v\n";

    my $comp_idx = 0;
    print OUT_QSF "\nset_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id component_partition\n";
    print OUT_QSF "set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id component_partition\n";
    foreach (@components) {
        print OUT_QSF "\nset_instance_assignment -name PARTITION_HIERARCHY component -to \"${_}:hls_component_dut_inst_${comp_idx}\" -section_id component_partition";
        $comp_idx = $comp_idx + 1;
    }

    if (defined $qii_seed ) {
        print OUT_QSF "\nset_global_assignment -name SEED $qii_seed";
    }

    close(OUT_QSF);
}

sub generate_sdc($$) {
  my ($qii_project_name, $clock2x_used) = @_;


  open (OUT_SDC, ">${qii_project_name}.sdc") or die;

  print OUT_SDC "create_clock -period 1 clock\n";                                                                                                          
  if ($clock2x_used) {                                                                                                                                        
    print OUT_SDC "create_clock -period 0.5 clock2x\n";                                                                                           
  }                                                                                                                                                           

  close (OUT_SDC);
}

sub generate_qii_project {

    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");

    my $qii_project_name = "qii_compile_top";

    my @components = get_generated_components();

    if (not -d "qii") {
        mkdir "qii" or mydie("Can't make dir qii: $!\n");
    }
    chdir "qii" or mydie("Can't change into dir qii: $!\n");

    my $clock2x_used = generate_top_level_qii_verilog($qii_project_name, @components);
    generate_qsf($qii_project_name, @components);
    generate_sdc($qii_project_name, $clock2x_used);

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    return $qii_project_name;
}

sub compile_qii_project($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir."/qii" or mydie("Can't change into dir $g_work_dir/qii: $!\n");

    @cmd_list = ('quartus_sh',
            #'--search-path='.$SEARCH_PATH,
            "--flow",
            "compile",
            "$qii_project_name");

    my $return_status = mysystem_full(
        {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'run QII compile'}, 
        @cmd_list);

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    return $return_status;
}

sub parse_qii_compile_results($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

}

sub run_quartus_compile {
    my $qii_project_name = generate_qii_project();
    compile_qii_project($qii_project_name);
    parse_qii_compile_results($qii_project_name);
}

sub main {
    parse_args();

    # Default to emulator
    if ( not $emulator_flow and not $simulator_flow ) {$emulator_flow = 1;}

    if ( $emulator_flow ) {$macro_type_string = "NONE";}
    else                  {$macro_type_string = "VERILOG";}

    # Process all source files one by one
    while ($#source_list >= 0) {
      my $source_file = shift @source_list;
      my $object_name = get_name_core($source_file).'.o';

      if ( $project_name && $object_only_flow_modifier) {
        # -c, so -o name applies to object file, don't add .o
        $object_name = $project_name;
      } 

      if ( $emulator_flow ) {
        emulator_compile($source_file, $object_name);
      } else {
        fpga_parse($source_file, $object_name);
        if (!$RTL_only_flow_modifier && !$soft_ip_c_flow_modifier) {
          testbench_parse($source_file, $object_name);
        }
      }
    }

    if ($object_only_flow_modifier) { myexit('Object generation'); }

    # Need to be here setup might redefine $project_name
    $executable=($project_name)?$project_name:'a.out';

    setup_linkstep(); #unpack objects and setup project directory

    # Now do the 'real' compiles depend link step, wich includes llvm cmpile for
    # testbench and components
    if ($#fpga_IR_list >= 0) {
      preprocess(); #Copy IP and others
      generate_fpga(@fpga_IR_list);
    }

    if ($qii_flow) {
      run_quartus_compile();
    }

    if ($RTL_only_flow_modifier) { myexit('RTL Only'); }

    if ($#tb_IR_list >= 0) {
      my $merged_file='tb.merge.bc';
      link_IR( $merged_file, @tb_IR_list);
      generate_testbench( $merged_file );
    }

    if ( $#object_list < 0) {
      hls_sim_generate_verilog($project_name);
    }   

    if ($#object_list >= 0) {
      link_x86($executable);
    }
    myexit("");
}

main;
