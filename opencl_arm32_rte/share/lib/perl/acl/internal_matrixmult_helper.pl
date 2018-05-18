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
    


# Intel(R) FPGA SDK for HLS compilation.
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
#        Subdirectory a.out.prj including key files:
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
require acl::Pkg;
require acl::Env;

#Always get the start time in case we vant to measure time
my $main_start_time = time(); 

my $prog = 'a++';
my $return_status = 0;

#Filenames
my @source_list = ();
my @object_list = ();
my @tmpobject_list = ();
my @fpga_IR_list = ();
my @tb_IR_list = ();
my @cleanup_list = ();
my @component_names = ();

my $project_name = undef;
my $keep_log = 0;
my $project_log = undef;
my $executable = undef;
my $board_variant=undef;
my $family = undef;
my $speed_grade = undef;
my $optinfile = undef;
my $pkg = undef;

#directories
my $orig_dir = undef; # path of original working directory.
my $g_work_dir = undef; # path of the project working directory as is.
my $quartus_work_dir = "quartus";
my $cosim_work_dir = "verification";
my $qii_project_name = "quartus_compile";

# Executables
my $clang_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $link_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-link";
my $llc_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $sysinteg_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/system_integrator";
my $mslink_exe = "link.exe";

#Flow control
my $emulator_flow = 0;
my $simulator_flow = 0;
my $RTL_only_flow_modifier = 0;
my $object_only_flow_modifier = 0;
my $soft_ip_c_flow_modifier = 0; # Hidden option for soft IP compilation
my $preprocess_only = 0;
my $macro_type_string = "";
my $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
my $cosim_debug = 0;
my $cosim_log_call_count = 0;

# Quartus Compile Flow
my $qii_flow = 0;
my $qii_vpins = 1;
my $qii_io_regs = 1;
my $qii_device = "Stratix V";
my $qii_seed = undef;
my $qii_fmax_constraint = undef;
my $qii_dsp_packed = 0; #if enabled, force aggressive DSP packing for Quartus compile results (ARRIA 10 only)

# Flow modifier
my $target_x86 = 0; # Hidden option for soft IP compilation to target x86
my $griffin_HT_flow = 0; # Use the DSPBA backend in place of HDLGen - high throughput (HT) flow
my $griffin_flow = 0; # Use the DSPBA backend in place of HDLGen
my $cosim_modelsim_ae = 0;
my $quartus_pro_flag = 0;

#Output control
my $verbose = 0; # Note: there are three verbosity levels now 1, 2 and 3
my $disassemble = 0; # Hidden option to disassemble the IR
my $dotfiles = 0;
my $save_tmps = 0;
my $debug_symbols = 1;      # Debug info enabled by default. Use -g0 to disable.
my $time_log = undef; # Time various stages of the flow; if not undef, it is a 
                      # file handle (could be STDOUT) to which the output is printed to.

#Command line support
my @cmd_list = ();
my @parseflags=();
my @linkflags=();
my @additional_opt_args   = (); # Extra options for opt, after regular options.
my @additional_llc_args   = ();
my @additional_sysinteg_args = ();

my $opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkzwewi22etqs0o0cvorlvczrk7mipp8xd3egwiyx713svzw3kmlt8clxdbqoypaxbbyw0oygu1nsyzekh3nt0x0jpsmvypfxguwwdo880qqk8pachqllyc18a7q3wp12j7eqwipxw13swz1bp7tk71wyb3rb17frk3egwiy2e7qjwoe3bkny8xrrdbq1w7ljg70g0o1xlbmupoecdfluu3xxf7l3dogxfs0lvm7jlzqjvo33gclly3xxf7mi8p32dc7udmirekmgvoy1bknyycrgfhmczpyxgf0wvz7jlzmy8p83kfnedxz2azqb17frk77qdiyxlkmh8ithkcluu3xxf7nvyzs2kmegdoyxlctgfptck3nt0318a7mcyz1xgu7uui3rezlg07ekh3lqjxtgdmnczpy2jtehdo3xyctgfpthjmljpbzgdmlb17frkuww0zwreeqapzkhholuu3xxf7nz8p3xguwypp3gw7mju7atjbnhdxmrjumipprxdceg0z880qqk8z2tk7qjjxbxacnzvpfxbbyw0otrebma8z2hdolkwx18a7m8jorxbbyw0o72eona8iekh3nyvb1rzbtijz82hkwhjibgwklgfptchqlyvc7rahm8w7ljg7wldzzxu13svz0cg1mt8c8gssmxw7ljg70tjzwgukmkyo03k7qjjxwgfzmb0ogrgswtfmirezqspo23kfnuwb1rdbtijz3gffwhpom2e3ldjpacvorlvcqgskq10pggju7ryomx713svzkhh3qhvccgammzpplxbbyw0ow2ekmavzuchfntwxzga33czpyrfu0evzp2qmqwvzltk72tfxm2kbmbjo8rg70qpow2wctgfptchhnl0b18a7q8vpm2kc7uvm7jlzma8pt3h72tfxmrafmiwoljg70kyitrykmrvzj3bknywbp2kbm8wpdxgc0uui0x1ctgfptchhnl0b18a7m3pp8rduwk0ovx713svzkhh3qhvccgammzpplxbbyw0obgl3mt8z2td72tfxmrafmiwoljg70qjobrlumju7atjfnljxwgpsmv0zlxgbwkpioglctgfpttkbql0318a7mo8zark37swiyxyctgfpttd3ny0b0jpsmvypfrfc7rwizgekmsyzy1bknypxuga3nczpyxdtwgdo1xwkmsjzy1bknyvcc2kmnc0prxdbwudmirecnujp83jcnuwbzxasqb17frkc0gdo880qqk8zwtjoluu3xxf7nz8p3xguwypp3gw7mju7atjqllvbyxffmodzgggbwtfmireznrpokcdorlvc8gd1qc87frk3egwiwrl3lw0oetd72tfxmxdhmidzrxgc0rdo880qqkvzshh3qhyx12kzmcw7ljg7wrporgukqgpoy1bknyvcc2aoncdom2vs0rpiogu3qgfpt3ghngpb18a7q3vpljg70qyiwgukmsvoktj3quu3xxfhmivolgfbyw0oy2qclgvoy1bknyybx2kfqo0pljg70rvi1glqqgwp3cvorlvc8xdon38zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7we0otrubmju7atjfnljxwgpsmv8ofgffweji880qqkwzbhh13jwb7rj33czpy2g10g0i12ectgfpttdqnq0bvgsom7jzerj38uui3ruzqk0oy1bknyjcr2a33czpy2gb0e0oy2temywoy1bkny8xxxkcnvvpagkuwwdo880qqkpp73h7mtfxmrjtq88zrxjuwwwo880qqkwz33k72tfxmgfcmv8zt8vs0r0zb2lcna8pl3a3lrjc0jpsmvypfrfc7rwizgekmsyzy1bknyvby2kuq187frkc0upo020qqk0o2thzmlwbfrkbm8w7ljg70yjiogebmawzt3k72tfxmxffqijom2gbwgwo7x713svzr3j1qj8x12k33czpy2jo0qdmirecls8pacfoljy3xxf1q8vzljg70tyi1xlklu8p3cvorlvc7raznbyi82vs0rpiixlkmsyzy1bknydxc2kkq88zmxbbyw0oz2wolhyz23kzmhpbxrzbtijzgggc7u8zn2ezqgvoy1bknywc32jbncw7ljg7wh8zo2lemryz3cfmlh8xmxk33czpy2k7wedmiretqs8zw3bknyvbyxamnc87frkuwwjzr2qqqu8pttdorlvc7rdcqb17frkt0tyi0xl1qgfpt3kbnevc7rahm8w7ljg7wk8z1glznhjp23horlvc12dumvyzsxg7etfmiretqsjoehd3nldxrrzbtijzqrkbwtfmiretqsjoehd3nldxqrj33czpy2kh0jpokru13svz23ksnldb1gpsmv8pl2gbyw0obgl3nu8patdqnyvb0jpsmvdol2gfwjdo7jlzqsjpr3bkny8cmxfbm8jolrf38uui3xwzqg07ekh3njvc7ra1q8dolxfhwtfmire3qkyzy1bkny0blgsol8folrj38uui3gu1qajpn3korlvcz2auq3yprxguwapow2qemsy7atj3qhjxlgd7lb17frk3egwizrl3lg0o23gbquu3xxf1qcjzlxbbyw0oprlemyy7atj3meyxwrauqxyit8vs0rvzv2q13svztthmlqycqxfuqivzt8vs0r0zb2lcna8pl3a3lrjc0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpygjuwsdzy20qqkpzkcf3nuvbyxk33czpyxgk0udi7jlzqu0od3gzqhyclrzbtijz72jm7qyokx713svzucfzqj8xngjcncwo1rg37two1xykqsdpy1bknyjcr2a33czpyxjzwjdz7x713svzwtjoluu3xxf7nz8p3xguwypp3gw7mju7atjfnjwblgj7q3ype2s38uui32qqquwotthsly8xxgdbtijzfrgbyw0olx713svz3tjmlq8clgsqnc87frkh0t8zm2w13svzutkcljyc3gfcncjot8vs0r0z32etqjpo23k7qq0318a7qcjzlxbbyw0on2qhlr0oekh3ly8xyxf1m80o8xbbyw0oprl7lgpo3tfqlhvcprzbtijz8rk1wepor2qslg07ekh3lljxlgahm8w7ljg7wu0o7x713svzuck3nt0318a7mxpofxbbyw0o0re1mju7atjqllvbyxffmodzgggbwtfmirecnujpqhdmnqy3xxfzqovpu2kh0uui32l1qa07ekh3lkpbcxdmnb8pljg70yjiogebmay7atjsntyx18a7m3jorrjbwtfmire3nu8pn3gmlqy3xxfkmb0ohxbbyw0omgyqmju7atj3meyxwrauqxyiljg7wyvz880qqkwzt3k72tfxmgssqc8zcrfz7tvzy2qqqh07ekh3ng8xzxfkqb17frkcegpoirumqspof3bkny0blgssq3pzt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7we0otrubmju7atjsntwxcxa3lb17frko7u8zbgwknju7atjfnljxwgpsmvjog2g3eepin2tctgfptch3njvb7rzbtijzugkowgdou20qqk8zahhhlh8cygd33czpyxjfwkdmirezmhjzekh3lypc22kbm1w7ljg7wr8z1glzmdy7atj3nldxrgdmn8ypdggmutfmire3qkyzy1bkny8xxxkcnvvpagkuwwdo880qqk0oj3gorlvcmxa1qo8z8rkuwwwo880qqkdoetjzmlpbz2hbmczpyrhbwgyi7xlctgfpthfolj8x2gh33czpyrjoewvm7jlzqddp3cf3nlyxngssmcw7ljg7wu0o7x713svzn3k1medcfrzbtijz12jk0wyz720qqkwze3jzntfxmxkcnidolrf38uui3xwzqg07ekh3lqjxcrkbtijzq2jh0ujzbrlqmju7atjbmtpbz2dulb17frkk0u8zm2w13svz8hdolt8xmgfcnc0zljg70gjzogu1qu07ekh3ltvc1rzbtijzggg7ek0oo2loqddpecvorlvclgd3loypy2kc7udmiretquyoy1bkny8c8xfbqb17frkh0q0ozx713svzdthhlky3xxf7mi8pu2hs0uvm7jlzma8pt3h72tfxm2jbq8ype2s38uui3xleqs0oekh3lhpbzrk7mi8ofxdbyw0o1glqqswoucfoluu3xxf7qvwot8vs0ryz7gukmh8iy1bkny8xxxkcnvvpagkuwwdo880qqkjznhh72tfxmxkumowos2ho0s0onrwctgfpt3holjjc12kbq38o1gg38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxmxdoliw7ljg7wk8zbgykqjwpekh3nq8cyrs33czpyxj70uvm7jlzmtyz23gbnf0318a7q88zq2d70udmireolgvos3f1myycqrzbtijzqrkbwtfmiremlgpokhkqquu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcqgskq10pggju7ryomx713svzdthcmtpbqxjuq3jzhxbbyw0o3xqbmsdpechorlvcngfml8yplgfbyw0obglzlgpo03ghll0318a7qoypy2g38uui32lcng07ekh3nudxxxacnb0ol2vs0r0oo2etqgvot3gknry3xxfmmi8ofxj7etfmirecldvzh3bknyyx1gabtijzyrgswypimx713svzn3k1medcfrzbtijzs2h70evm7jlzqt8pktjsluu3xxfhmiyzqrfc7w8z7ru3lwwpecvorlvcvxjzqoypfrfbwgjz880qqkpoe3hmlhyclgs1qoypb2j38uui3xwzqg07ekh3ly8cl2kumcdo8xdueedo880qqkwzt3k72tfxm2kbq3wp0rdz0qjo880qqkjokhh72tfxmxjfq8jpgxdb0edmirekmswo23gknj8xmxkbtijzsrgz7u8z7guctgfpt3honqjxlgh7l3dol2kk0qyimx713svzdthmltvbyxamncjom2sh0uvm7jlzquvzuchmljpb1rdbnv0ogrgswtfmirezqsdpn3k1qhy3xxfuqi0olrjbwgdmireuqrwp03g7qq8x12k7lb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0rpo0gq1luwoekh3nj8xagd7lb17frko7u8zbgwknju7atjblky3xxf3n3joh2vs0rdiextctgfpthk7mtfxmrs1q80zlggbwuvm7jlzmhyo33korlvcy2kumxvpfrgk0ujzr2qzqgfpthkoqlvcygsfqijot8vs0ryoeru1qgfpt3jzltvbu2fbtijze2ds0rjzbrlqqu07ekh3ltjxu2fhmc87frk37kdiy20qqkdz83bknyybxgsclb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0ryoyre13svzw3k3nlyxwxa7nz0ogrgswtfmirekmsvo0tjhnqpcz2abqb17frkc0rdo880qqkdz8tjorlvcmxasq28z1rfu0wyi7jlzmyyo3cg72tfxm2d3nv87frk70wyil2wolu8pshhorlvclgdkmiporxg38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzmh0ot3bknywcf2a1moypy2vs0rpop2q7ms07ekh3nedxqrj7mi8pu2hs0uvm7jlzmgvzecvorlvc32jsqb17frk77qdiyxlkmh8ithkcluu3xxf7nz8p3xguwypp7jlzmh0oy1bknywcmgd33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg7wewioxu13svz33gslkwxz2dulb17frkm7ujoere1qgfptckolkycxrdbqijzl2vs0rjobru3ljdpt3k72tfxmgfml8yzx2vs0rvzr2qmnju7atj1mtyxc2jbmczpy2ds0jpoixy1mgy7atj3nuwxvxk33czpyxgf0tjotxyemuyz3cfqqqyc0jpsmvdodxgh0uui3xukmyyzd3gknt0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijzs2hk0qjz7jlzqkjpatjoqjpb12a7m7w7ljg70tyiirl3ljwoe3bknyyx1gacmcwot8vs0rpiiru1muwoekh3nj8vxxfbtijzu2dowydorructgfpt3jklljxygfcnc87frk7wqpoigl1may7atjznt0b12acmcppy2hb0gvm7jlzmh0oq3jqllwcrgfmn8w7ljg70g0obgyctgfpthkbngwc0jpsmvjosgd38uui3gekmry7atjsnudxzrk33czpyxfm7udmiretqsjp83bkny0bzrkbqoypf2hs0yvm7jlzmuyzfthbmty3xxfcm3wos2h70tjz720qqkwzrtk72tfxmxdoliw7ljg70qyitxyzqsypr3gknt0318a7qcypfxdbwtfmirebmgvzecvorlvcqxfuq2w7ljg7wewioxu13svz83g7mtwxz2auqivzt8vs0rpiiru3lkjpfhjqllyc0jpsmv0zy2j38uui3gu1qajpn3korlvc8gj3loypy2kc7udmire3mkjzy1bknyvbzga3loype2s7wywo880qqkwpstfoljvbtgscnvwpt8vs0rjooxy13svzthkcntfxmrafmiwoljg7whpiy2wtqddpkhhcluu3xxfzmcwoljg7wewiq2wolddpqcvorlvcz2a7l3jzd2gm0qyi7x713svz33gslkwxz2dunvpzwxbbyw0o0re1mju7atjblky3xxftmbdoq2js0ujo7jlzqjvzt3fsluu3xxfoq187frkt0t8z02wqqgwzekh3ltjxyrzbtijzggg7ek0oo2loqddpecvorlvcqgskq10pggju7ryomx713svzwtjoluu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcrgdmnzpzxxbbyw0onxleqjwokhhclkjxz2acn80oxxgbwtfmirezmuyzucfontfxmxkcnb0ps2vs0ryor2w1qgfpttjfnhvbygdmn8w7ljg70gdop2wzmry7atj3le8cz2abtijzdxfcetfmire3qkyzy1bkny8xxxkcnvvpagkuwwdo880qqk8zwhgomjwb18a7m8ypb2j7etfmiremlgpokhkqquu3xxfmnc0znrkb0uui3gwbmsjp7cf72tfxm2fmncyzj2vs0rdi72l3qg0oy1bknywcmgd33czpygfb0gwieguzqgy7atj3qe8clgssmxw7ljg70rji72eqqr0oekh3njjx2rjbtijzgxf38uui3xyhmujp7tkelkybygpsmvwo12hswkvm7jlzmtyz23gbnf0318a7qxwow2ko7u8zbgwknjf0a';

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my @llvm_board_option = ();

# checks host OS, returns true for linux, false for windows.
sub isLinuxOS {
    if ($^O eq 'linux') {
      return 1; 
    }
    return;
}

# checks for Windows host OS. Returns true if Windows, false if Linux.
# Uses isLinuxOS so OS check is isolated in single function.
sub isWindowsOS {
    if (isLinuxOS()) {
      return;
    }
    return 1;
}

sub mydie(@) {
    if(@_) {
        print STDERR "Error: ".join("\n",@_)."\n";
    }
    chdir $orig_dir if defined $orig_dir;
    push @cleanup_list, $project_log unless $keep_log;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 1;
}

sub myexit(@) {
    if ($time_log) {
      log_time ('Total time ending @'.join("\n",@_), time() - $main_start_time);
      close ($time_log);
    }

    print STDERR 'Success: '.join("\n",@_)."\n" if $verbose>1;
    chdir $orig_dir if defined $orig_dir;
    push @cleanup_list, $project_log unless $keep_log;
    remove_named_files(@cleanup_list) unless $save_tmps;
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
    my $start_time = time();
    my $retcode = system(@cmd);
    my $end_time = time();

    # Restore STDOUT/STDERR if they were replaced.
    if($out) {
      close(STDOUT) or mydie "Couldn't close STDOUT: $!";
      open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
    }
    if($err) {
      close(STDERR) or mydie "Couldn't close STDERR: $!";
      open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
    }

    # Dump out time taken if we're tracking time.
    if ($time_log) {
      if (!$title) {
        # Just use the command as the label.
        $title = join(' ',@cmd);
      }
      log_time ($title, $end_time - $start_time);
    }

    my $result = $retcode >> 8;

    if($retcode != 0) {
      if ($result == 0) {
        # We probably died on an assert, make sure we do not return zero
        $result=-1;
      } 
      my $loginfo = "";
      if($err && $out && ($err != $out)) {
        $keep_log = 1;
        $loginfo = "\nSee $err and $out for details.";
      } elsif ($err) {
        $keep_log = 1;
        $loginfo = "\nSee $err for details.";
      } elsif ($out) {
        $keep_log = 1;
        $loginfo = "\nSee $out for details.";
      }
      print("HLS $title FAILED.$loginfo\n");
    }
    return ($result);
}

sub log_time($$) {
  my ($label, $time) = @_;
  if ($time_log) {
    printf ($time_log "[time] %s ran in %ds\n", $label, $time);
  }
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
    acl::File::remove_tree($file); # Remove immediatly don't wait for cleanup
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

sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose>2), dry_run => 0 } )
         or mydie("Cannot remove $fname: $acl::File::error\n");
    }
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
      push @cleanup_list, $work_dir;
    }
}

# Strips leading directories and removes any extension
sub get_name_core($) {
    my  $base = acl::File::mybasename($_[0]);
    $base =~ s/[^a-z0-9_\.]/_/ig;
    my $suffix = $base;
    $suffix =~ s/.*\.//;
    $base=~ s/\.$suffix//;
    return $base;
}

sub print_debug_log_header($) {
    my $cmd_line = shift;
    open(LOG, ">>$project_log");
    print LOG "*******************************************************\n";
    print LOG " a++ debug log file                                    \n";
    print LOG " This file contains diagnostic information. Any errors \n";
    print LOG " or unexpected behavior encountered when running a++   \n";
    print LOG " should be reported as bugs. Thank you.                \n";
    print LOG "*******************************************************\n";
    print LOG "\n";
    print LOG "Compiler Command: ".$cmd_line."\n";
    print LOG "\n";
    close LOG
}

sub setup_linkstep ($) {
    my $cmd_line = shift;
    # Setup project directory and log file for reminder of compilation
    # We could deduce this from the object files, but that is known at unpacking
    # that requires this to be defined.
    # Only downside of this is if we use a++ to link "real" objects we also reate
    # create an empty project directory
    if (!$project_name) {
        $project_name = 'a.out';
    }
    $g_work_dir = ${project_name}.'.prj';
    # No turning back, remove anything old
    remove_named_files($g_work_dir,'modelsim.ini',$project_name);

    acl::File::make_path($g_work_dir) or mydie($acl::File::error.' While trying to create '.$g_work_dir);
    $project_log=${g_work_dir}.'/debug.log';
    $project_log = acl::File::abs_path($project_log);
    print_debug_log_header($cmd_line);
    # Remove immediatly. This is to make sure we don't pick up data from 
    # previos run, not to clean up at the end 

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

Usage: a++ [<options>] <input_files> 
Generic flags:
--version   Display compiler version information
-v          Verbose mode
-h,--help   Display this information
-o <name>   Place the output into <name> and <name>.prj
--debug-log Generate the compiler diagnostics log

Flags impacting the compile step (source to object file translation):
-march=<arch> 
            Generate code for <arch>, <arch> is one of:
              x86-64, altera
-c          Preprocess, parse and generate object files
--rtl-only  Generate RTL for components without testbench
--quartus-compile 
            Run HDL through a Quartus compilation
--component <components>
            Comma-separated list of function names to synthesize to RTL
--promote-integers  
            Use extra FPGA resources to mimic g++ integer promotion
-D<macro>[=<val>]   
            Define a <macro> with <val> as its value.  If just <macro> is
            given, <val> is taken to be 1
-g          Generate debug information (default)
-g0         Don't generate debug information
-I<dir>     Add directory to the end of the main include path

Flags impacting the link step only (object file to binary/RTL translation):
--device <device>       
            Specifies the FPGA device or family to use, <device> is one of:
              "Stratix V", "Arria 10", "Cyclone V", "Max 10", or any valid
              part number from those FPGA families
--clock <clock_spec>
            Optimize the RTL for the specified clock frequency or period
--fp-relaxed 
            Relax the order of arithmetic operations
--fpc       Removes intermediate rounding and conversion when possible
-L<dir>     Add directory dir to the list of directories to be searched for -l
-l<library> Search the library named library when linking
-ghdl       Enable full debug visibility and logging of all HDL signals in simulaion
USAGE

}

sub version($) {
    my $outfile = $_[0];
    print $outfile "a++ Compiler for Altera High Level Synthesis\n";
    print $outfile "Version 0.3 Build 192\n";
    print $outfile "Copyright (C) 2016 Intel Corporation\n";
}

sub norm_family_str {
    my $strvar = shift;
    # strip whitespace
    $strvar =~ s/[ \t]//gs;
    # uppercase the string
    $strvar = uc $strvar;
    return $strvar;
}

sub device_get_family_no_normalization {  # DSPBA needs the original Quartus format
    my $local_start = time();
    my $qii_family_device = shift;
    my $family_from_quartus = `quartus_sh --tcl_eval get_part_info -family $qii_family_device`;
    # Return only what's between the braces, without the braces 
    ($family_from_quartus) = ($family_from_quartus =~ /\{(.*)\}/);
    chomp $family_from_quartus;
    log_time ('Get device family', time() - $local_start) if ($time_log);
    return $family_from_quartus;
}

sub device_get_family {
    my $qii_family_device = shift;
    my $family_from_quartus = device_get_family_no_normalization( $qii_family_device );
    $family_from_quartus = norm_family_str($family_from_quartus);
    return $family_from_quartus;
}

sub device_get_speedgrade {  # DSPBA requires the speedgrade to be set, in addition to the part number
    my $local_start = time();
    my $device = shift;
    my $speed_grade_from_quartus = `quartus_sh --tcl_eval get_part_info -speed_grade $device`;
    mydie("Failed to determine speed grade of device $device\n") if (!defined $speed_grade_from_quartus);
    # Some speed grade results from quartus include the transciever speed grade appended to the core speed grade.
    # We extract the first character only to be sure that we have exclusively the core result.
    log_time ('Get speed grade', time() - $local_start) if ($time_log);
    return "-".substr($speed_grade_from_quartus, 0, 1);  # Prepend '-' because DSPBA expects it
}

sub translate_device {
  my $qii_dev_family = shift;
    $qii_dev_family = norm_family_str($qii_dev_family);
    my $qii_device = undef;

    if ($qii_dev_family eq "ARRIA10") {
        $qii_device = "10AX115U1F45I1SG";
    } elsif ($qii_dev_family eq "STRATIXV") {
        $qii_device = "5SGSMD4E1H29I2";
    } elsif ($qii_dev_family eq "CYCLONEV") {
        $qii_device = "5CEFA9F23I7";
    } elsif ($qii_dev_family eq "MAX10") {
        $qii_device = "10M50DAF672I7G";
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


sub create_reporting_tool {
  my $filelist = shift;
  local $/ = undef;

  acl::File::copy_tree(acl::Env::sdk_root()."/share/lib/acl_report/lib", "$g_work_dir/reports");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/Report.htm", "$g_work_dir/reports/report.html");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/main.js", "$g_work_dir/reports/lib/main.js");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/main.css", "$g_work_dir/reports/lib/main.css");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/spv/graph.js", "$g_work_dir/reports/lib/graph.js");

  open (my $report, ">$g_work_dir/reports/lib/report_data.js") or mydie("Could not open file report_data.js $!");

  open (my $area, '<', $g_work_dir.'/area.json') or mydie("Could not open file area.json $!");
  my $areaJSON = <$area>;
  close($area);

  open (my $mav, '<', $g_work_dir.'/mav.json') or mydie("Could not open file mav.json $!");
  my $mavJSON = <$mav>;
  close($mav);  

  open (my $loops, '<', $g_work_dir.'/loops.json') or mydie("Could not open file loops.json $!");
  my $loopsJSON = <$loops>;
  close($loops);  

  print $report "var loopsJSON=";   
  print $report $loopsJSON.";";

  print $report "var mavJSON=";
  print $report $mavJSON.";";
  
  print $report "var areaJSON=";   
  print $report $areaJSON.";";

  print $report "var fileJSON=";
  my $count = 0;
  my $filepath = "";
  my $filename = "";
  my @fileJSON;
  my @tempfilepath;

  foreach my $filein ( split(/\n/, $filelist) ) {
    if ($filein =~ m/\<unknown\>$/) {
      next;
    }

    if ($count) { 
      print $report ", {";
    } else {
      print $report "[{";
    }

    print $report '"index":'.$count;
    print $report ', "path":"'.$filein.'"';

    @tempfilepath = (split /\//, $filein);
    $filename = pop @tempfilepath;
    print $report ', "name":"'.$filename.'"';

    open (my $fin, '<', "$filein") or die "Could not open file $!";
    my $filecontent = <$fin>;
    close($fin);

    # $filecontent needs to be escaped since this in an input string which may have
    # quotes, and special characters. These can lead to invalid javascript which will
    # break the reporting tool.
    # The input from loops.json, area.json and mav.json is already valid JSON
    $filecontent =~ s/(\012|\015\012|\015\015\012?)/\\012/g;
    $filecontent =~ s/(?<!\\)\\n/\\\\n/g;
    $filecontent =~ s/(?<!\\)\\t/\\\\t/g;
    $filecontent =~ s/(?<!\\)\\f/\\\\f/g;
    $filecontent =~ s/(?<!\\)\\b/\\\\b/g;
    $filecontent =~ s/(?<!\\)\\r/\\\\r/g;
    $filecontent =~ s/(?<!\\)\"/\\"/g;
    print $report ', "content":"'.$filecontent.'"}';

    $count = $count + 1;
  }
  print $report "];";
  close($report);
}

sub save_and_report{
    my $local_start = time();
    my $filename = shift;
    my $report_dir = "$g_work_dir/reports";
    acl::File::make_path($report_dir) or die;;
    my $pkg = create acl::Pkg(${report_dir}.'/'.get_name_core(${project_name}).'.aoco');

    my $files;
    # Visualization support
    if ( $debug_symbols ) { # Need dwarf file list for this to work
      $files = `file-list \"$g_work_dir/$filename\"`;
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
          save_pkg_section($pkg,'.acl.file.'.$index,$file);
          $pkg->add_file('.acl.source.'. $index,$file)
            or mydie("Can't save source into package file: $acl::Pkg::error\n");
          $index = $index + 1;
      }
      save_pkg_section($pkg,'.acl.nfiles',$index);
    }

    if (not $griffin_flow) {
      create_reporting_tool($files);
    }

    # Save Loops Report JSON file 
    my $loops_file = $g_work_dir.'/loops.json';
    if ( -e $loops_file ) {
      $pkg->add_file('.acl.loops.json', $loops_file)
          or mydie("Can't save loops.json into package file: $acl::Pkg::error\n");
      push @cleanup_list, $loops_file;
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
    if ( ! -e $area_file_html and $verbose > 0 ) {
      print "Missing area report information\n";
    }
    acl::File::copy($area_file_html, "$report_dir/area.html");
    push @cleanup_list, $area_file_html;
    # Get rid of SPV JSON file ince we don't use it 
    my $spv_file = $g_work_dir.'/spv.json';
    if ( -e $spv_file ) {
      push @cleanup_list, $spv_file;
    }
    # Optimization report
    my $opt_rpt = $g_work_dir.'/opt.rpt';
    acl::File::copy($opt_rpt, "$report_dir/optimization.rpt");
    push @cleanup_list, $opt_rpt;
    # Quartus report
    open(QRPT_FILE, ">$report_dir/quartus.rpt") or die;
    print QRPT_FILE "# This report contains a summary of the area and fmax data generated by\n";
    print QRPT_FILE "# compiling the components through Quartus.  To generate the data, run\n";
    print QRPT_FILE "# a Quartus compile on the project created for this design.\n";
    print QRPT_FILE "#\n";
    print QRPT_FILE "# To run the Quartus compile:\n";
    print QRPT_FILE "#   1) Change to the quartus directory ($g_work_dir/quartus)\n";
    print QRPT_FILE "#   2) quartus_sh --flow compile quartus_compile\n";
    close(QRPT_FILE);

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    
    log_time ('Create Report', time() - $local_start) if ($time_log);
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

    my $fmax = undef;

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
    if (defined $fmax) { 
        $fmax = $fmax/1000000;
    }
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
      elsif ( ($arg eq '-g') ) { 
          $debug_symbols = 1;
	  # if the user explicitly requests debug symbols and we're running on a Windows OS,
	  # dont't enable debug symbols.
	  if (isWindowsOS()) {
	      $debug_symbols = 0;
	      print "$prog: Debug symbols are not supported in emulation mode on Windows, ignoring -g.\n";
	  }
      }
      elsif ( ($arg eq '-g0') ) { $debug_symbols = 0;}
      elsif ( ($arg eq '-o') ) {
          # Absorb -o argument, and don't pass it down to Clang
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
          $project_name = shift @ARGV;
      }
      elsif ( ($arg eq '--component') ) {
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie('Option --component requires a function name');
          push @component_names, shift @ARGV;
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
      elsif ($arg eq '--cosim-debug' ||
             $arg eq '-ghdl') {
          $RTL_only_flow_modifier = 0;
          $cosim_debug = 1;
      }
      elsif ($arg eq '--cosim-modelsim-ae') {
          $cosim_modelsim_ae = 1;
      }
      elsif ($arg eq '--cosim-log-call-count') {
          $cosim_log_call_count = 1;
      }
      elsif ( ($arg eq '--clang-arg') ) {
          $#ARGV >= 0 or mydie('Option --clang-arg requires an argument');
          # Just push onto args list
          push @user_parseflags, shift @ARGV;
      }
      elsif ( ($arg eq '--debug-log') ) {
        $keep_log = 1;
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
      elsif ($arg eq '--dot') {
        $dotfiles = 1;
      }
      elsif ($arg eq '--save-temps') {
        $save_tmps = 1;
      }
      elsif ($arg eq '--fold') {
        mydie('Option --fold not supported');
      }
      elsif ($arg eq '--grif') {
        $griffin_HT_flow = 1;
        $griffin_flow = 1;
      }
      elsif ( ($arg eq '--clock') ) {
          my $clk_option = (shift @ARGV);
          $qii_fmax_constraint = clk_get_fmax($clk_option);
          if (!defined $qii_fmax_constraint) {
              mydie("a++: bad value ($clk_option) for --clock argument\n");
          }
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
      elsif ($arg eq '--generate-altera-ip') {
          #Temporary fix until MegaCore can add --llc-arg to their arg list
          push(@additional_llc_args, $arg);
      }
      elsif ($arg eq '--quartus-compile') {
          $qii_flow = 1;
      }
      elsif ($arg eq '--quartus-no-vpins') {
          $qii_vpins = 0;
      }
      elsif ($arg eq '--quartus-dont-register-ios') {
          $qii_io_regs = 0;
      }
      elsif ($arg eq '--quartus-aggressive-pack-dsps') {
          $qii_dsp_packed = 1;
      }
      elsif ($arg eq "--device") {
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie('Option --device requires a device name');
          $qii_device = shift @ARGV;
      }
      elsif ($arg eq "--quartus-seed") {
          $qii_seed = shift @ARGV;
      }
      elsif ($arg eq '--time') {
        if($#ARGV >= 0 && $ARGV[0] !~ m/^-./) {
          $time_log = shift(@ARGV);
        }
        else {
          $time_log = "-"; # Default to stdout.
        }
      }
      elsif ($arg eq "--pro") {
        $quartus_pro_flag = 1;
      }
      elsif ($arg =~ /^-[lL]/ or
             $arg =~ /^-Wl/) { 
          push @user_linkflags, $arg;
      }
      elsif ($arg eq '-I') { # -Iinc syntax falls through to default below (even if first letter of inc id ' '
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
          push  @user_parseflags, $arg.(shift @ARGV);
      }
      elsif ( $arg =~ m/\.c$|\.cc$|\.cp$|\.cxx$|\.cpp$|\.CPP$|\.c\+\+$|\.C$/ ) {
          push @source_list, $arg;
      }
      elsif ( $arg =~ m/\.o$/ ) {
          push @object_list, $arg;
      } 
      elsif ($arg eq '-E') { #preprocess only;
          $preprocess_only= 1;
          $object_only_flow_modifier= 1;
          push @user_parseflags, $arg 
      } else {
          push @user_parseflags, $arg 
      }
    }

    # if $debug_symbols is set and we're running on
    # a Windows OS, disable debug symbols silently here
    # since the default is to generate debug_symbols.
    if ($debug_symbols && isWindowsOS()) {
      $debug_symbols = 0;
    }

    # Default to emulator
    if ( not $emulator_flow and not $simulator_flow ) {$emulator_flow = 1;}

    if (@component_names) {
      push @user_parseflags, "-Xclang";
      push @user_parseflags, "-soft-ip-c-func-name=".join(',',@component_names);
    }

    # All arguments in, make sure we have at least one file
    (@source_list + @object_list) > 0 or mydie('No input files');
    if ($debug_symbols) {
      push @user_parseflags, '-g';
      push @additional_llc_args, '-dbg-info-enabled';
    } 

    if ($RTL_only_flow_modifier && $emulator_flow ) {
      mydie("a++: The --rtl-only flag is valid only with -march=altera\n");
    }

    open_time_log_file();

    $qii_device = translate_device($qii_device);

    # only query the family name if using a sim flow,
    # currently this queries Quartus and takes about 10 seconds
    # on our development sessions.
    #
    if ($simulator_flow) { 
        $family = device_get_family($qii_device); 
        if ($family eq "") {
            mydie("Device $qii_device is not known, please specify a known device\n");
        }
    }

    ($family, $board_variant) = parse_family($family);

    # Make sure that the qii compile flow is only used with the altera compile flow
    if ($qii_flow and not $simulator_flow) {
        mydie("The --quartus-compile argument can only be used with -march=altera\n");
    }
    # Check qii flow args
    if ((not $qii_flow) and $qii_dsp_packed) {
        mydie("The --quartus-aggressive-pack-dsps argument must be used with the --quartus-compile argument\n");
    }
    if ($qii_dsp_packed and not ($family eq "ARRIA10")) {
        mydie("The --quartus-aggressive-pack-dsps argument is only applicable to the Arria 10 device family\n");
    }

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
    if (isLinuxOS()) {
      push (@linkflags, '-lstdc++');
      push (@linkflags, '-L'.$host_lib_path);
    }
}

sub fpga_parse ($$){  
    my $source_file= shift;
    my $objfile = shift;
    print "Analyzing $source_file for hardware generation\n" if $verbose;

    $pkg = undef;

    # OK, no turning back remove the old result file, so no one thinks we 
    # succedded. Can't be defered since we only clean it up IF we don't do -c
    acl::File::remove_tree($objfile);
    if ($preprocess_only || !$object_only_flow_modifier) { push @cleanup_list, $objfile; };

    $pkg = create acl::Pkg($objfile);
    push @object_list, $objfile;

    my $work_dir=$objfile.'.'.$$.'.tmp';
    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
    push @cleanup_list, $work_dir;

    my $outputfile=$work_dir.'/fpga.ll';

    my @clang_std_opts2 = qw(-S -x hls -emit-llvm -Wuninitialized -fno-exceptions);
    if ( $target_x86 == 0 ) {
      if (isLinuxOS()) {
        push (@clang_std_opts2, qw(-ccc-host-triple fpga64-unknown-linux));
      } elsif (isWindowsOS()) {
        push (@clang_std_opts2, qw(-ccc-host-triple fpga64-unknown-win32));
      }
    }

    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts2,
      "-D__ALTERA_TYPE__=$macro_type_string",
      @parseflags,
      $source_file,
      $preprocess_only ? '':('-o',$outputfile)
    );

    $return_status = mysystem_full( {'title' => 'FPGA Parse'}, @cmd_list);
    if ($return_status) {
        push @cleanup_list, $objfile; #Object file created
        mydie();
    }
    if (!$preprocess_only) {
        # add 
        $pkg->add_file('.hls.fpga.parsed.ll',$outputfile);
        push @cleanup_list, $outputfile;
    }
}

sub testbench_parse ($$) {
    my $source_file= shift;
    my $object_file = shift;
    print "Analyzing $source_file for testbench generation\n" if $verbose;

    my $work_dir=$object_file.'.'.$$.'.tmp';
    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
    push @cleanup_list, $work_dir;

    #Temporarily disabling exception handling here, Tracking in FB223872
    my @clang_std_opts = qw(-S -emit-llvm  -x hls -O0 -Wuninitialized -fno-exceptions);

    if ($cosim_modelsim_ae) {
        push @clang_std_opts, '-m32';
    }

    my @macro_options;
    @macro_options= qw(-DHLS_COSIMULATION -Dmain=__altera_hls_main);

    my $outputfile=$work_dir.'/tb.ll';
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts,
      "-D__ALTERA_TYPE__=$macro_type_string",
      @parseflags,
      @macro_options,
      $source_file,
      $preprocess_only ? '':('-o',$outputfile)
      );

    $return_status = mysystem_full( {'title' => 'Testbench parse'}, @cmd_list);
    if ($return_status != 0) {
        push @cleanup_list, $object_file; #Object file created
        mydie();;
    }
    if (!$preprocess_only) {
        $pkg->add_file('.hls.tb.parsed.ll',$outputfile);
        push @cleanup_list, $outputfile;
    }
}

sub emulator_compile ($$) {
    my $source_file= shift;
    my $object_file = shift;
    print "Analyzing $source_file for emulation\n" if $verbose;
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      qw(-x hls -O0 -Wuninitialized -c),
      '-DHLS_EMULATION',
      "-D__ALTERA_TYPE__=$macro_type_string",
      $source_file,
      @parseflags,
      $preprocess_only ? '':('-o',$object_file)
    );
    
    mysystem_full(
      {'title' => 'Emulator compile'}, @cmd_list) == 0 or mydie();
    
    push @object_list, $object_file;
    if (!$object_only_flow_modifier) { push @cleanup_list, $object_file; };
}

sub generate_testbench(@) {
    my ($IRfile)=@_;
    print "Creating x86-64 testbench \n" if $verbose;

    my $resfile=$g_work_dir.'/tb.bc';
    my @flow_options= qw(-replacecomponentshlssim);

    @cmd_list = (
      $opt_exe,  
      @flow_options,
      @additional_opt_args,
      @llvm_board_option,
      '-o', $resfile,
      $g_work_dir.'/'.$IRfile );
    mysystem_full( {'title' => 'Testbench component wrapper generation'}, @cmd_list) == 0 or mydie();
    disassemble($resfile);
    
    push @cleanup_list, $resfile;
    
    my @clang_std_opts = qw(-B/usr/bin -fPIC -shared -O0);

    my @cosim_libs;

    if ($cosim_modelsim_ae) {
        push @clang_std_opts, '-m32';
        push @cosim_libs, '-lhls_cosim32'
    } else {
        push @cosim_libs, '-lhls_cosim'
    }

    if (not -d "$g_work_dir/$cosim_work_dir") {
      mkdir "$g_work_dir/$cosim_work_dir" or mydie ("Can't make directory $cosim_work_dir: $!\n");
    }

    my $soname;

    if (isLinuxOS()) {
      $soname = get_name_core(${project_name}).'.so';
      @cmd_list = (
        $clang_exe,
        ($verbose>2)?'-v':'',
        @clang_std_opts,
        $g_work_dir.'/tb.bc',
        "-D__ALTERA_TYPE__=$macro_type_string",
        @object_list,
        '-Wl,-soname,'.$soname,
        '-o', "$g_work_dir/$cosim_work_dir/$soname",
        @linkflags, @cosim_libs );
    } elsif (isWindowsOS()) { 
      $soname = get_name_core(${project_name}).'.dll';
      @cmd_list = (
        $clang_exe, '-c',
        ($verbose>2)?'-v':'',
        @clang_std_opts,
        $g_work_dir.'/tb.bc',
        "-D__ALTERA_TYPE__=$macro_type_string",
        @object_list);

      mysystem_full({'title' => 'Clang (Compiling executable testbench image)'}, @cmd_list ) == 0 or mydie();

      mysystem_full({'stdout' => $project_log, , 'stderr' => $project_log, 'title' => 'Rename tb.o to proj dir'},'mv','tb.o',$g_work_dir.'/'.$cosim_work_dir.'/tb.o' ) == 0 or mydie();

      my $abs_hls_libpath = acl::File::abs_path(acl::Env::sdk_root().'/windows64/lib/hls_cosim.lib');

      unless (-e $abs_hls_libpath) {
        mydie("hls_cosim.lib does not exist\n");
      }

      @cmd_list = (
        $mslink_exe, 
        $g_work_dir.'/'.$cosim_work_dir.'/tb.o',
        '-dll','-nologo', 
        '-export:__altera_hls_main', 
        '-nodefaultlib:libcmt',
        '-out:'."$g_work_dir/$cosim_work_dir/$soname",
        $abs_hls_libpath);
    } else {
      mydie("Unsupported OS detected\n");
    }

    mysystem_full({'title' => 'Clang (Linking executable testbench image)'}, @cmd_list ) == 0 or mydie();

    # we used the regular objects, remove them so we don't think this is emulation
    @object_list=();
}




sub generate_fpga(@){
    my @IR_list=@_;
    print "Optimizing component(s) and generating Verilog files\n" if $verbose;

    my $linked_bc=$g_work_dir.'/fpga.linked.bc';

    # Link with standard library.
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_early.bc');
    @cmd_list = (
      $link_exe,
      @IR_list,
      $early_bc,
      '-o',
      $linked_bc );
    
    mysystem_full( {'title' => 'Early IP Link'}, @cmd_list) == 0 or mydie();
    
    disassemble($linked_bc);
    
    # llc produces visualization data in the current directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    my $kwgid='fpga.opt.bc';
    my @flow_options = qw(-HLS);
    if ( $soft_ip_c_flow_modifier ) { push(@flow_options, qw(-SIPC)); }
    if ( $griffin_flow ) { push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false)); }
    my @cmd_list = (
      $opt_exe,
      @flow_options,
      split( /\s+/,$opt_passes),
      @llvm_board_option,
      @additional_opt_args,
      'fpga.linked.bc',
      '-o', $kwgid );
    mysystem_full( {'title' => 'Main Optimizer'}, @cmd_list ) == 0 or mydie();
    disassemble($kwgid);
    if ( $soft_ip_c_flow_modifier ) { myexit('Soft IP'); }

    # Lower instructions to IP library function calls
    my $lowered='fpga.lowered.bc';
    @flow_options = qw(-HLS -insert-ip-library-calls);
    if ( $griffin_flow ) { push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false)); }
    @cmd_list = (
        $opt_exe,
        @flow_options,
        @additional_opt_args,
        $kwgid,
        '-o', $lowered);
    mysystem_full( {'title' => 'Lower intrinsics to IP calls'}, @cmd_list ) == 0 or mydie();

    # Link with the soft IP library 
    my $linked='fpga.linked2.bc';
    my $late_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_late.bc');
    @cmd_list = (
      $link_exe,
      $lowered,
      $late_bc,
      '-o', $linked );
    mysystem_full( {'title' => 'Late IP library'}, @cmd_list)  == 0 or mydie();

    # Inline IP calls, simplify and clean up
    my $final = get_name_core(${project_name}).'.bc';
    @cmd_list = (
      $opt_exe,
      qw(-HLS -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk),
      @llvm_board_option,
      @additional_opt_args,
      $linked,
      '-o', $final);
    mysystem_full( {'title' => 'Inline and clean up'}, @cmd_list) == 0 or mydie();
    disassemble($final);
    push @cleanup_list, $g_work_dir."/$final";

    my $llc_option_macro = $griffin_flow ? ' -march=griffin ' : ' -march=fpga -mattr=option3wrapper -fpga-const-cache=1';
    my @llc_option_macro_array = split(' ', $llc_option_macro);
    if ( $griffin_flow ) { push(@additional_llc_args, qw(--grif)); }

    # DSPBA backend needs to know the device that we're targeting
    if ( $griffin_flow ) { 
      my $grif_device;
      if ( $qii_device ) {
        $grif_device = $qii_device;
      } else {
        $grif_device = get_default_qii_device();
      }
      push(@additional_llc_args, qw(--device));
      push(@additional_llc_args, qq($grif_device) );

      # DSPBA backend needs to know the device family - Bugz:309237 tracks extraction of this info from the part number in DSPBA
      # Device is defined by this point - even if it was set to the default.
      # Query Quartus to get the device family`
      mydie("Internal error: Device unexpectedly not set") if (!defined $grif_device);
      my $grif_family = device_get_family_no_normalization($grif_device); 
      push(@additional_llc_args, qw(--family));
      push(@additional_llc_args, "\"".$grif_family."\"" );

      # DSPBA backend needs to know the device speed grade - Bugz:309237 tracks extraction of this info from the part number in DSPBA
      # The device is now defined, even if we've chosen the default automatically.
      # Query Quartus to get the device speed grade.
      mydie("Internal error: Device unexpectedly not set") if (!defined $grif_device);
      my $grif_speedgrade = device_get_speedgrade( $grif_device );
      push(@additional_llc_args, qw(--speed_grade));
      push(@additional_llc_args, qq($grif_speedgrade) );
    }

    @cmd_list = (
        $llc_exe,
        @llc_option_macro_array,
        qw(-HLS),
        qw(--board hls.xml),
        @additional_llc_args,
        $final,
        '-o',
        get_name_core($project_name).'.v' );
    mysystem_full({'title' => 'Verilog code generation, llc'}, @cmd_list) == 0 or mydie();

    my $xml_file = get_name_core(${project_name}).'.bc.xml';
    mysystem_full(
      {'title' => 'System Integration'},
      ($sysinteg_exe, @additional_sysinteg_args,'--hls', 'hls.xml', $xml_file )) == 0 or mydie();

    my @components = get_generated_components();
    my $ipgen_result = create_qsys_components(@components);
    mydie("Failed to generate Qsys files\n") if ($ipgen_result);

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    #Cleanup everything but final bc
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.*.bc" );
    push @cleanup_list, $g_work_dir."/$xml_file";
    push @cleanup_list, $g_work_dir.'/hls.xml';
    push @cleanup_list, $g_work_dir.'/'.get_name_core($project_name).'.v';
    push @cleanup_list, $g_work_dir.'/opt.rpt.xml';
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.attrib" );
    push @cleanup_list, $g_work_dir.'/interfacedesc.txt';
    push @cleanup_list, $g_work_dir.'/compiler_metrics.out';

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

    mysystem_full( {'title' => 'Link IR'}, @cmd_list) == 0 or mydie();

    disassemble($full_name);
}

sub link_x86 ($) {
    my $output_name = shift ;

    print "Linking x86 objects\n" if $verbose;
    
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      "-D__ALTERA_TYPE__=$macro_type_string",
      @object_list,
      '-o',
      $executable,
      @linkflags
      );

    if (isLinuxOS()) {
      push @cmd_list, '-lhls_emul';
    }
    
    mysystem_full( {'title' => 'Emulator Link'}, @cmd_list) == 0 or mydie();

    return;
}

sub get_generated_components() {
  # read the comma-separated list of components from a file
  my $project_bc_xml_filename = get_name_core(${project_name}).'.bc.xml';
  my $BC_XML_FILE;
  open (BC_XML_FILE, "<${project_bc_xml_filename}") or mydie "Couldn't open ${project_bc_xml_filename} for read!\n";
  my @dut_array;
  while(my $var =<BC_XML_FILE>) {
    if ($var =~ /<KERNEL name="(.*)" filename/) {
        push(@dut_array,$1); 
    }
  }
  close BC_XML_FILE;
  return @dut_array;
}

sub hls_sim_generate_verilog(@) {
    my $projdir = acl::File::mybasename($g_work_dir);
    print "Generating cosimulation support\n" if $verbose;
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my @dut_array = get_generated_components();
    # finally, recreate the comma-separated string from the array with unique elements
    my $DUT_LIST  = join(',',@dut_array);
    print "Generating simulation files for components: $DUT_LIST\n" if $verbose;
    my $SEARCH_PATH = acl::Env::sdk_root()."/ip/,.,../components/**/*,\$"; # no space between paths!

    # Setup file path names
    my $tbname    = 'altera_verification_testbench';

    # Because the qsys-script tcl cannot accept arguments, 
    # pass them in using the --cmd option, which runs a tcl cmd
    #
    # Set default value of $count_log
    my $count_log = "\\\"\\\"";
    if (isWindowsOS()) {
      # FB 393064: There's some wonkiness with setting count_log
      # to same as what's used in Linux for default value, so we set
      # count_log to something for now. Look at this later.
      $count_log = "sim_component_call_count.log";
    }

    if ($cosim_log_call_count) {
      $count_log = "$projdir/sim_component_call_count.log";
    }
    my $init_var_tcl_cmd = "set sim_qsys $tbname; set component_list $DUT_LIST; set component_call_count_filename ".$count_log;

    # Create the simulation directory and enter it
    my $sim_dir_abs_path = acl::File::abs_path("./$cosim_work_dir");
    print "HLS simulation directory: $sim_dir_abs_path.\n" if $verbose;
    acl::File::make_path($cosim_work_dir) or mydie("Can't create simulation directory $sim_dir_abs_path: $!");
    chdir $cosim_work_dir or mydie("Can't change into dir $cosim_work_dir: $!\n");

    my $gen_qsys_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_sim_generate_qsys.tcl";

    # Run hls_sim_generate_qsys.tcl to generate the .qsys file for the simulation system 
    my $pro_string = "";
    if ($quartus_pro_flag) { $pro_string = "--pro --quartus-project=none"; }
    mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log, 'title' => 'Generate testbench QSYS system'},
      'qsys-script '.$pro_string.' --search-path='.$SEARCH_PATH.' --script='.$gen_qsys_tcl.' --cmd="'.$init_var_tcl_cmd.'"')  == 0 or mydie();

    # Generate the verilog for the simulation system
    @cmd_list = ('qsys-generate',
      '--search-path='.$SEARCH_PATH,
      '--simulation=VERILOG',
      '--family='.$family,
      '--part='.$qii_device,
      $tbname.'.qsys');
    if ($quartus_pro_flag) { push(@cmd_list, '--pro'); }
    mysystem_full(
      {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'Generate testbench Verilog from QSYS system'}, 
      @cmd_list)  == 0 or mydie();

    # Generate scripts that the user can run to perform the actual simulation.
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    generate_simulation_scripts($tbname);
}


# This module creates a file:
# Moved everything into one file to deal with run time parameters, i.e. execution directory vs scripts placement.
#Previous do scripts are rewritten to strings that gets put into the run script
#Also perl driver in project directory is gone.
#  - compile_do      (the string run by the compilation phase, in the output dir)
#  - simulate_do     (the string run by the simulation phase, in the output dir)
#  - <source>        (the executable top-level simulation script, in the top-level dir)
sub generate_simulation_scripts(@) {
    my ($tbname) = @_;

    # Working directories
    my $qsysdir = $tbname.'/'.get_qsys_output_dir("SIM_VERILOG");
    my $projdir = acl::File::mybasename($g_work_dir);
    my $simscriptdir = $qsysdir.'/mentor';
    my $cosimdir = "$g_work_dir/$cosim_work_dir";
    # Script filenames
    my $fname_compilescript = $simscriptdir.'/msim_compile.tcl';
    my $fname_runscript = $simscriptdir.'/msim_run.tcl';
    my $fname_msimsetup = $simscriptdir.'/msim_setup.tcl';
    my $fname_svlib = get_name_core(${project_name});
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';

    # Modify the msim_setup script
    post_process_msim_file("$cosimdir/$fname_msimsetup", "$simscriptdir");
    
    # Generate the modelsim compilation script
    my $COMPILE_SCRIPT_FILE;
    open(COMPILE_SCRIPT_FILE, ">", "$cosimdir/$fname_compilescript") or mydie "Couldn't open $cosimdir/$fname_compilescript for write!\n";
    print COMPILE_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print COMPILE_SCRIPT_FILE "set QSYS_SIMDIR $simscriptdir/..\n";
    print COMPILE_SCRIPT_FILE "source $fname_msimsetup\n";
    print COMPILE_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC";
    print COMPILE_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                            : "\"\n");
    print COMPILE_SCRIPT_FILE "dev_com\n";
    print COMPILE_SCRIPT_FILE "com\n";
    print COMPILE_SCRIPT_FILE "elab\n";
    if (isWindowsOS()) {

      $executable .= "\.cmd";

      my $abs_hls_libpath_windows = acl::File::abs_path(acl::Env::sdk_root().'/windows64/lib/hls_cosim.lib');
      unless (-e $abs_hls_libpath_windows) {
        mydie("hls_cosim.lib does not exist\n");
      }
      my $msim_location = acl::File::which_full ("vsim"); chomp $msim_location;
      if ( not defined $msim_location ) {
        mydie("Error: Modelsim path is not found!\n");
      }
      ## convert backslashes to forward slashes
      $msim_location=~ tr{\\}{/};
      ## convert all uppercase letters to lower case
      $msim_location=~ tr/A-Z/a-z/;
      ## we found vsim.exe, translate to mtipli.lib (the library we link to)
      my $vsimexe = "vsim\.exe";
      my $mtilib  = "mtipli\.lib";
      $msim_location=~ s/$vsimexe/$mtilib/g;
      unless (-e $msim_location) {
        mydie("mtipli.lib does not exist, or Modelsim path is invalid.\n");
      }
      print COMPILE_SCRIPT_FILE "elab -dpiexportobj exportobj.obj\n";
      print COMPILE_SCRIPT_FILE "exec link -nodefaultlib:libcmt -nologo -dll -out:a.dll tb.o exportobj.obj ",
    		  	 "$abs_hls_libpath_windows ",
                         "$msim_location ",
			 "-export:__altera_hls_dbgs ",
			 "-export:__altera_hls_stream_ready ",
			 "-export:__altera_hls_stream_write ",
			 "-export:__altera_hls_stream_front ",
			 "-export:__altera_hls_stream_read ",
			 "-export:__altera_hls_run_tb ",
			 "-export:__altera_hls_stream_empty ",
			 "-export:__altera_hls_get_component_call_count ",
			 "-export:__altera_hls_get_stream_obj_ptr_for_component_interface\n";

    }
    print COMPILE_SCRIPT_FILE "exit -code 0\n";
    close(COMPILE_SCRIPT_FILE);

    # Generate the run script
    my $RUN_SCRIPT_FILE;
    open(RUN_SCRIPT_FILE, ">", "$cosimdir/$fname_runscript") or mydie "Couldn't open $cosimdir/$fname_runscript for write!\n";
    print RUN_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print RUN_SCRIPT_FILE "set QSYS_SIMDIR $simscriptdir/..\n";
    print RUN_SCRIPT_FILE "source $fname_msimsetup\n";
    print RUN_SCRIPT_FILE "# Suppress warnings from the std arithmetic libraries\n";
    print RUN_SCRIPT_FILE "set StdArithNoWarnings 1\n";
    print RUN_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib $fname_svlib";
    print RUN_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                        : "\"\n");
    print RUN_SCRIPT_FILE "elab\n";
    print RUN_SCRIPT_FILE "onfinish {stop}\n";
    print RUN_SCRIPT_FILE "log -r *\n" if $cosim_debug;
    print RUN_SCRIPT_FILE "run 1ps\n";
    print RUN_SCRIPT_FILE "cd \${rundir}\n";
    print RUN_SCRIPT_FILE "run -all\n";
    print RUN_SCRIPT_FILE "set failed [expr [coverage attribute -name TESTSTATUS -concise] > 1]\n";
    print RUN_SCRIPT_FILE "exit -code \${failed}\n";
    close(RUN_SCRIPT_FILE);

    # Generate the executable script
    my $EXE_FILE;
    open(EXE_FILE, '>', $executable) or die "Could not open file '$executable' $!";
    if (isLinuxOS()) {
      print EXE_FILE "#!/bin/sh\n";
      print EXE_FILE "\n";
      print EXE_FILE "# Identify the directory to run from\n";
      print EXE_FILE "# Run the testbench\n";
      print EXE_FILE "rundir=\$PWD\n";
      print EXE_FILE "scripthome=\$(dirname \$0)\n";
      print EXE_FILE "cd \${scripthome}/$projdir/$cosim_work_dir\n";
      print EXE_FILE "vsim -batch -nostdout -keepstdout -l transcript.log -stats=none -do \"set rundir \${rundir}; do $fname_runscript\"\n";
      print EXE_FILE "if [ \$? -ne 0 ]; then\n";
      print EXE_FILE "  >&2 echo \"ModelSim simulation failed.  See $cosimdir/transcript.log for more information.\"\n";
      print EXE_FILE "  cd \${rundir}\n";
      print EXE_FILE "  exit 1\n";
      print EXE_FILE "fi\n";
      print EXE_FILE "cd \${rundir}\n";
      print EXE_FILE "exit 0\n";
      close(EXE_FILE);
      system("chmod +x $executable");
    } elsif (isWindowsOS()) {

      print EXE_FILE "\@echo off\n";
      print EXE_FILE "set PWD=%~dp0\n";
      print EXE_FILE "set PWD=%PWD:\\=/%\n";
      print EXE_FILE "cd  %PWD%/$projdir/$cosim_work_dir\n";
      print EXE_FILE "vsim -batch -nostdout -keepstdout -l transcript.log -stats=none -do \"set rundir %PWD%; do $fname_runscript\"\n";
      print EXE_FILE "IF %ERRORLEVEL% NEQ 0 (\n";
      print EXE_FILE "  ECHO Modelsim simulation failed. See $cosim_work_dir/transcript.log for more information.\n";
      print EXE_FILE "  set exitCode=1\n";
      print EXE_FILE ") ELSE (\n";
      print EXE_FILE "  ECHO Modelsim simulation successful!\n";
      print EXE_FILE "  set exitCode=0\n";
      print EXE_FILE ")\n";
      print EXE_FILE "cd %PWD%\n";
      print EXE_FILE "exit /b %exitCode%\n";
      close(EXE_FILE);
    } else {
      mydie();
    }

    # Generate a script that we'll call to compile the design
    my $EXE_COM_FILE;
    open(EXE_COM_FILE, '>', "$cosimdir/$fname_exe_com_script") or die "Could not open file '$cosimdir/$fname_exe_com_script' $!";
    if (isLinuxOS()) {
      print EXE_COM_FILE "#!/bin/sh\n";
      print EXE_COM_FILE "\n";
      print EXE_COM_FILE "# Identify the directory to run from\n";
      print EXE_COM_FILE "rundir=\$PWD\n";
      print EXE_COM_FILE "scripthome=\$(dirname \$0)\n";
      print EXE_COM_FILE "cd \${scripthome}\n";
      print EXE_COM_FILE "# Compile and elaborate the testbench\n";
      print EXE_COM_FILE "vsim -batch -do \"do $fname_compilescript\"\n";
      print EXE_COM_FILE "retval=\$?\n";
      print EXE_COM_FILE "cd \${rundir}\n";
      print EXE_COM_FILE "exit \${retval}\n";
    } elsif (isWindowsOS()) {
      print EXE_COM_FILE "set PWD=\%\~dp0\n";
      print EXE_COM_FILE "cd  %PWD%/$projdir/$cosim_work_dir\n";
      print EXE_COM_FILE "vsim -batch -do \"set rundir \%PWD\%; do $fname_compilescript\"\n";
      print EXE_COM_FILE "IF %ERRORLEVEL% NEQ 0 (\n";
      print EXE_COM_FILE "  ECHO Compile failed. See $cosim_work_dir/transcript.log for more information.\n";
      print EXE_COM_FILE "  set exitCode=1\n";
      print EXE_COM_FILE ") ELSE (\n";
      print EXE_COM_FILE "  ECHO Compile successful!\n";
      print EXE_COM_FILE "  set exitCode=0\n";
      print EXE_COM_FILE ")\n";
      print EXE_COM_FILE "cd %PWD%\n";
      print EXE_COM_FILE "exit /b %exitCode%\n";
    } else {
      mydie("Unsupported OS detected\n");
    }
    close(EXE_COM_FILE);
    system("chmod +x $cosimdir/$fname_exe_com_script"); 
}

sub compile_verification_project() {
    # Working directories
    my $cosimdir = "$g_work_dir/$cosim_work_dir";
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';
    # Compile the cosim design in the cosim directory
    $orig_dir = acl::File::abs_path('.');
    chdir $cosimdir or mydie("Can't change into dir $g_work_dir: $!\n");
    if (isLinuxOS()) {
      @cmd_list = ("./$fname_exe_com_script");
    } elsif (isWindowsOS()) {
      @cmd_list = ("$fname_exe_com_script");
    } else {
      mydie("Unsupported OS detected\n");
    }

    $return_status = mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log,
       'title' => 'Elaborate verification testbench'},
      @cmd_list);
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    # Missing license is such a common problem, let's give a special message
    if($return_status == 4) {
      mydie("Missing simulator license.  Either:\n" .
            "  1) Ensure you have a valid ModelSim license\n" .
            "  2) Use the --rtl-only flag to skip the verification flow\n");
    } elsif($return_status == 127) {
    # same for Modelsim not installed on the PATH
        mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
              "       Check your ModelSim installation with \"vmap -version\" \n"); 
    } elsif($return_status != 0) {
      mydie("Cosim testbench elaboration failed.\n");
    }
}

sub gen_qsys_script(@) {
    my @components = @_;


    foreach (@components) {
        # Generate the tcl for the system
        my $tclfilename = "$_.tcl";
        open(my $qsys_script, '>', "$tclfilename") or die "Could not open file '$tclfilename' $!";

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
set_instance_property ${_}_internal_inst AUTO_EXPORT true

# save the Qsys file
save_system "$_.qsys"
SCRIPT
        close $qsys_script;
        push @cleanup_list, $g_work_dir."/$tclfilename";
    }
}

sub run_qsys_script(@) {
    my @components = @_;

    foreach (@components) {
        # Generate the verilog for the simulation system
        @cmd_list = ('qsys-script',
                     '--search-path=.',
                     "--script=$_.tcl");
        if ($quartus_pro_flag) { push(@cmd_list, ('--pro', '--quartus-project=none')); }
        mysystem_full(
            {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'Generate component QSYS script'}, 
            @cmd_list) == 0 or mydie();
    }
}

sub post_process_msim_file(@) {
  my ($file,$libpath) = @_;
  open(FILE, "<$file") or die "Can't open $file for read";
  my @lines;
  while(my $line = <FILE>) {
    $line =~ s|\./libraries/|$libpath/libraries/|g;
    push(@lines,$line);
  }
  close(FILE);
  open(OFH,">$file") or die "Can't open $file for write";
  foreach my $line (@lines) {
    print OFH $line;
  }
  close(OFH);
  return 0;
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

sub create_ip_folder(@) {
  my @components = @_;
  my $OCLROOTDIR = $ENV{'ALTERAOCLSDKROOT'};
  foreach (@components) {
    my $component = $_;
    open(FILELIST, "<$component.files") or die "Can't open $component.files for read";
    while(my $file = <FILELIST>) {
      chomp $file;
      if($file =~ m|\$::env\(ALTERAOCLSDKROOT\)/|) {
        $file =~ s|\$::env\(ALTERAOCLSDKROOT\)/||g;
        acl::File::copy("$OCLROOTDIR/$file", "components/".$component."/".$file);
      } else {
        acl::File::copy($file, "components/".$component."/".$file);
        push @cleanup_list, $g_work_dir.'/'.$file;
      }
    }
    close(FILELIST);
    acl::File::copy($component.".qsys", "components/".$component."/".$component.".qsys");
    push @cleanup_list, $g_work_dir.'/'.$component.".qsys";
    push @cleanup_list, $g_work_dir.'/'.$component.".files";
  }
  acl::File::copy("interface_structs.v", "components/interface_structs.v");
  push @cleanup_list, $g_work_dir.'/interface_structs.v';
  return 0;
}

sub create_qsys_components(@) {
    my @components = @_;
    gen_qsys_script(@components);
    run_qsys_script(@components);
    post_process_qsys_files(@components);
    create_ip_folder(@components);
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
    my %clock2x_used;
    my %component_portlists;
    foreach (@components) {
      #read in component module from file and parse for portlist
      my $example = '../components/'.$_.'/'.$_.'_inst.v';
      open (FILE, "<$example") or die "Can't open $example for read";
      #parse for portlist
      my $in_module = 0;
      while (my $line = <FILE>) {
        if($in_module) {
          if($line =~ m=^ *\.([a-z]+)=) {
          }
          if($line =~ m=^\s*\.(\S+)\s*\( \), // (\d+)-bit \S+ (input|output)=) {
            my $hi = $2 - "1";
            my $range = "[$hi:0]";
            push(@{$component_portlists{$_}}, {'dir' => $3, 'range' => $range, 'name' => $1});
            if($1 eq "clock2x") {
              push(@{$clock2x_used{$_}}, 1);
            }
          }
        } else {
          if($line =~ m|^$_ ${_}_inst \($|) {
            $in_module = 1;
          }
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
    if (scalar keys %clock2x_used) {
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
        print OFH "\n\n\t${_} ${_}_inst (\n";
        print OFH "\t\t  .resetn(resetn)\n";
        print OFH "\t\t, .clock(clock)\n";
        if (exists $clock2x_used{$_}) {
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

    return scalar keys %clock2x_used;
}

sub generate_qsf($@) {
    my ($qii_project_name, @components) = @_;

    my $qii_vpin_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_create_vpins.tcl";

    open (OUT_QSF, ">${qii_project_name}.qsf") or die;
    print OUT_QSF "# This Quartus settings file sets up a project to measure the area and fmax of\n";
    print OUT_QSF "# your components in a full Quartus compilation for the targeted device\n";
    print OUT_QSF "\n";
    print OUT_QSF "# Family and device are derived from the --device argument to a++\n";
    print OUT_QSF "set_global_assignment -name FAMILY \"${family}\"\n";
    print OUT_QSF "set_global_assignment -name DEVICE ${qii_device}\n";

    print OUT_QSF "\n";
    print OUT_QSF "# This script configures all component I/Os as virtual pins to more accurately\n";
    print OUT_QSF "# model placement and routing in a larger system\n";
    my $qii_vpins_comment = "# ";
    if ($qii_vpins) {
      $qii_vpins_comment = "";
    }
    print OUT_QSF $qii_vpins_comment."set_global_assignment -name POST_MODULE_SCRIPT_FILE \"quartus_sh:${qii_vpin_tcl}\"\n";
    print OUT_QSF "# This script parses the Quartus reports and generates a summary in reports/quartus.rpt\n";
    # add call to parsing script after STA is run
    my $qii_rpt_tcl = "generate_report.tcl";
    print OUT_QSF "set_global_assignment -name POST_FLOW_SCRIPT_FILE \"quartus_sh:${qii_rpt_tcl}\"\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Files implementing a basic registered instance of each component\n";
    print OUT_QSF "set_global_assignment -name TOP_LEVEL_ENTITY ${qii_project_name}\n";
    print OUT_QSF "set_global_assignment -name SDC_FILE ${qii_project_name}.sdc\n";
    # add component Qsys files to project
    foreach (@components) {
      print OUT_QSF "set_global_assignment -name QSYS_FILE ../components/$_/$_.qsys\n";
    }
    # add generated top level verilog file to project
    print OUT_QSF "set_global_assignment -name SYSTEMVERILOG_FILE ${qii_project_name}.v\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Partitions are used to separate the component logic from the project harness when tallying area results\n";
    print OUT_QSF "set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id component_partition\n";
    print OUT_QSF "set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id component_partition\n";
    foreach (@components) {
      print OUT_QSF "set_instance_assignment -name PARTITION_HIERARCHY component -to \"${_}:${_}_inst\" -section_id component_partition\n";
    }

    print OUT_QSF "\n";
    print OUT_QSF "# Use the --quartus-seed flag to a++, or modify this setting to run other seeds\n";
    my $seed = 0;
    my $seed_comment = "# ";
    if (defined $qii_seed ) {
      $seed = $qii_seed;
      $seed_comment = "";
    }
    print OUT_QSF $seed_comment."set_global_assignment -name SEED $seed";

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

sub generate_quartus_ini() {
  open(OUT_INI, ">quartus.ini") or die;
  #temporary work around for A10 compiles
  if ($family eq "ARRIA10") {
    print OUT_INI "a10_iopll_es_fix=off\n";
  }
  if ($qii_dsp_packed) {
    print OUT_INI "fsv_mac_merge_for_density=on\n";
  }
  close(OUT_INI);
}

sub generate_report_script($@) {
  my ($qii_project_name, $clock2x_used, @components) = @_;
  my $qii_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_report.tcl";
  open(OUT_TCL, ">generate_report.tcl") or die;
  print OUT_TCL "# This script has the logic to create a summary report\n";
  print OUT_TCL "source $qii_rpt_tcl\n";
  print OUT_TCL "# These are generated by a++ based on the components\n";
  print OUT_TCL "set show_clk2x   $clock2x_used\n";
  print OUT_TCL "set components   [list " . join(" ", @components) . "]\n";
  print OUT_TCL "# This is where we'll generate the report\n";
  print OUT_TCL "set report_name  \"../reports/quartus.rpt\"\n";
  print OUT_TCL "# These get sent to the script by Quartus\n";
  print OUT_TCL "set project_name [lindex \$quartus(args) 1]\n";
  print OUT_TCL "set project_rev  [lindex \$quartus(args) 2]\n";
  print OUT_TCL "# This call creates the report\n";
  print OUT_TCL "generate_report \$project_name \$project_rev \$report_name \$show_clk2x \$components\n"; 
  close(OUT_TCL);
}

sub generate_qii_project {
    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my @components = get_generated_components();
    if (not -d "$quartus_work_dir") {
        mkdir "$quartus_work_dir" or mydie("Can't make dir $quartus_work_dir: $!\n");
    }
    chdir "$quartus_work_dir" or mydie("Can't change into dir $quartus_work_dir: $!\n");

    my $clock2x_used = generate_top_level_qii_verilog($qii_project_name, @components);
    generate_report_script($qii_project_name, $clock2x_used, @components);
    generate_qsf($qii_project_name, @components);
    generate_sdc($qii_project_name, $clock2x_used);
    generate_quartus_ini();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
}

sub compile_qii_project($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir."/$quartus_work_dir" or mydie("Can't change into dir $g_work_dir/$quartus_work_dir: $!\n");

    @cmd_list = ('quartus_sh',
            "--flow",
            "compile",
            "$qii_project_name");

    mysystem_full(
        {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'run Quartus compile'}, 
        @cmd_list) == 0 or mydie();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    return $return_status;
}

sub open_time_log_file {
  # Process $time_log. If defined, then treat it as a file name 
  # (including "-", which is stdout).
  # Code copied from aoc.pl
  if ($time_log) {
    my $fh;
    if ($time_log ne "-") {
      # Overwrite the log if it exists
      open ($fh, '>', $time_log) or mydie ("Couldn't open $time_log for time output.");
    } else {
      # Use STDOUT.
      open ($fh, '>&', \*STDOUT) or mydie ("Couldn't open stdout for time output.");
    }
    # From this point forward, $time_log is now a file handle!
    $time_log = $fh;
  }
}

sub run_quartus_compile($) {
    my ($qii_project_name) = @_;
    print "Run Quartus\n" if $verbose;
    compile_qii_project($qii_project_name);
}

sub main {
    my $cmd_line = $prog . " " . join(" ", @ARGV);
    parse_args();

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

    setup_linkstep($cmd_line); #unpack objects and setup project directory

    # Now do the 'real' compiles depend link step, wich includes llvm cmpile for
    # testbench and components
    if ($#fpga_IR_list >= 0) {
      preprocess(); # Find board
      generate_fpga(@fpga_IR_list);
    }

    if ($#tb_IR_list >= 0) {
      my $merged_file='tb.merge.bc';
      push @cleanup_list, $merged_file;
      link_IR( $merged_file, @tb_IR_list);
      generate_testbench( $merged_file );
    }
    push @cleanup_list, $g_work_dir."/tb.merge.bc";

    if ( $#object_list < 0) {
      hls_sim_generate_verilog(get_name_core($project_name));
      generate_qii_project();
    }   

    if ($RTL_only_flow_modifier) { myexit('RTL Only'); }

    # Run Quartus, ModelSim compilation, or x86 link step
    if ($qii_flow) {
      run_quartus_compile($qii_project_name);
    } elsif( $#object_list < 0) {
      compile_verification_project();
    } else {
      link_x86($executable);
    }

    myexit("Main flow");
}

main;
