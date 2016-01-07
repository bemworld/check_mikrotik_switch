#!/usr/bin/perl -w

use strict;
use Net::SNMP;
use Set::IntSpan;
use Getopt::Long qw(:config no_ignore_case);

my $snmpSession;
my $host = '127.0.0.1';
my $community = 'public';
my $warn;
my $crit;
my $stat = 0;
my $msg = '';
my $perf = '';
my $type;
my @ports;

my %checkTypeNeedsPorts = map {$_ => 1} qw(portName portOperState portAdminState portMtu portMacAddress portRxDiscards portTxDiscards portTxErrors portRxErrors portRxPackets portTxPackets portTxBytes portRxBytes );

# port statistics are returned as sum, except for those defined in %doNotSumValues.
# checks with value != undef can only handle one port.
my %doNotSumValues = (
    'portName'        => undef,
    'portOperState'  => '',
    'portAdminState' => '',
    'portMtu'         => '',
    'portMacAddress' => undef
);

my %oids = (
    'cpu'                  => ".1.3.6.1.2.1.25.3.3.1.2.1",
    'activeFan'            => '.1.3.6.1.4.1.14988.1.1.3.9.0',
    'voltage'              => '.1.3.6.1.4.1.14988.1.1.3.8.0',
    'temperature'          => '.1.3.6.1.4.1.14988.1.1.3.10.0',
    'processorTemperature' => '.1.3.6.1.4.1.14988.1.1.3.11.0',
    'current'              => '.1.3.6.1.4.1.14988.1.1.3.13.0',
    'powerConsumption'     => '.1.3.6.1.4.1.14988.1.1.3.12.0',
    'psu1State'            => '.1.3.6.1.4.1.14988.1.1.3.15.0',
    'psu2State'            => '.1.3.6.1.4.1.14988.1.1.3.16.0',
    'diskTotal'            => ".1.3.6.1.2.1.25.2.3.1.5.1",
    'diskUsed'             => ".1.3.6.1.2.1.25.2.3.1.6.1",
    'memTotal'             => ".1.3.6.1.2.1.25.2.3.1.5.2",
    'memUsed'              => ".1.3.6.1.2.1.25.2.3.1.6.2",
    'portName'             => '.1.3.6.1.2.1.2.2.1.2',
    'portOperState'        => '.1.3.6.1.2.1.2.2.1.8',
    'portAdminState'       => '.1.3.6.1.2.1.2.2.1.7',
    'portMtu'              => '.1.3.6.1.2.1.2.2.1.4',
    'portMacAddress'       => '.1.3.6.1.2.1.2.2.1.6',
    'portRxDiscards'       => '.1.3.6.1.2.1.2.2.1.13',
    'portTxDiscards'       => '.1.3.6.1.2.1.2.2.1.19',
    'portTxErrors'         => '.1.3.6.1.2.1.2.2.1.20',
    'portRxErrors'         => '.1.3.6.1.2.1.2.2.1.14',
    'portRxPackets'        => '.1.3.6.1.2.1.31.1.1.1.7',
    'portTxPackets'        => '.1.3.6.1.2.1.31.1.1.1.11',
    'portTxBytes'          => '.1.3.6.1.2.1.31.1.1.1.10',
    'portRxBytes'          => '.1.3.6.1.2.1.31.1.1.1.6'
);

sub usage {
    my $message = $_[0];
    
    if (defined $message && length $message) {
      $message .= "\n" unless $message =~ /\n$/;
   }
   print $message;
   my $command = $0;
   $command =~ s#^.*/##;
   
   print STDERR qq{
$message

Usage:
    ${0} 
         -H <ip-address>
         [-C <community>]
         -t <test type>
         [-i <switch ports>]
         -w <warn range>
         -c <crit range>
         
    Parameters:
        -H <ip-address>     The IP address or the host name of the switch
        [-C <community>]    The SNMP community string (default: public) [optional]
        -t <test type>      The test type to execute. See below.
        -w <warn range>     Range for result WARNING, see https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
        -c <crit range>     Range for result CRITICAL, see https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
            
    Additional parameter, depending on test (testname starts with "port"):
        -i <switch ports>   single, multiple and ranges possible, for example: 1,5-10,22-24
    
    The following test types are available (-t):
            cpu                  
            activeFan            
            voltage              
            temperature          
            processorTemperature 
            current              
            powerConsumption     
            psu1State            
            psu2State            
            diskTotal            
            diskUsed             
            memTotal             
            memUsed              
            portName             
            portOperState        
            portAdminState       
            portMtu              
            portMacAddress       
            portRxDiscards       
            portTxDiscards       
            portTxErrors         
            portRxErrors         
            portRxPackets        
            portTxPackets        
            portTxBytes          
            portRxBytes    
    
    All port results are added up, except for 'portName', 'portOperState', 'portAdminState', 'portMtu', 'portMacAddress'
    
    }
    
}


sub expandPorts {
    my ($optName, $optValue) = @_;
    my $span = Set::IntSpan->new($optValue);
    @ports = $span->elements();
}

sub expandAndValidateRanges {
    my ($optName, $optValue) = @_;
    
    my $range = {
        from    => 0, 
        negInf  => 0, 
        to      => 0, 
        posInf  => 1, 
        alertIf => 'outside'
    };
    
    if($optValue =~ qr/^(\@)?((?:~?)|(?:-?\d+)(?:\.\d+)?)(:)?(-?\d+(?:\.\d+)?)?$/){
        if ($1){
            $range->{alertIf} = 'inside'
        }
        
        if($2){
            if($2 eq '~'){
                $range->{negInf} = 1;
            }else{
                $range->{from} = $2;
            }
        }
        
        if($4){
            $range->{to} = $4;
            $range->{posInf} = 0;
        }
        
        if ($range->{posInf} == 0 && $range->{negInf} == 0 && $range->{from} >= $range->{to}) {
            print "Invalid range definition for -$optName option\n";
            exit 3;
        }
        
        if($optName eq 'w'){
            $warn = $range;
        }else{
            $crit = $range;
        }
       
    }else{
        print "Invalid -$optName value, must be in nagios range format [@][start:]end\n";
        exit 3;
    }
}

sub alertByRange{
    my ($range, $value) = @_;
    my $ok = 0;
    my $alert = 1;
    if ($range->{alertIf} eq 'inside') {
        $ok = 1;
        $alert = 0;
    }
    if ($range->{posInf} == 0 && $range->{negInf} == 0) {
        if ($range->{from} <= $value && $value <= $range->{to}) {
            return $ok;
        } else {
            return $alert;
        }
    } elsif ($range->{negInf} == 0 && $range->{posInf} == 1) {
        if ( $value >= $range->{from} ) {
            return $ok;
        } else {
            return $alert;
        }
    } elsif ($range->{negInf} == 1 && $range->{posInf} == 0) {
        if ($value <= $range->{to}) {
            return $ok;
        } else {
            return $alert;
        }
    } else {
        return $ok;
    }
}

sub createSession {
    my ($switch, $comm) = @_;
    my $snmpVersion = '2c';
    my ($session, $error) = Net::SNMP->session(
        -hostname       => $host,
        -community      => $community,
        -version        => $snmpVersion
    );
    if ($error || !defined($session)) {
        printf('Failed to establish SNMP session (%s)', $error);
        exit 3;
    }
    return $session;
}

sub exitUnknown {
    my ($message, $error) = @_;
    print "$message: $error\n";
    $snmpSession->close;
    exit 3;
}

GetOptions(
    'H=s'   => \$host,
    'C=s'   => \$community,
    'w=s'   => \&expandAndValidateRanges,
    'c=s'   => \&expandAndValidateRanges,
    't=s'   => \$type,
    'i=s'   => \&expandPorts
) or usage("Invalid commmand line options.");
 
if (!(defined $oids{$type} || $type eq 'mem' || $type eq 'disk')){
    usage("Check type $type not supported");
    exit 3;
}

if ($checkTypeNeedsPorts {$type} && !@ports) {
    usage("For check type $type, port list must not be empty");
    exit 3;
}

if (defined $doNotSumValues{$type} && @ports != 1) {
    usage("For check type $type, only one port is allowed");
    exit 3;
}

$snmpSession = createSession($host,$community);

if ($checkTypeNeedsPorts {$type}) {
    my $ret;
    foreach my $port (@ports) {
    
        my $oid = "$oids{$type}.$port";
        my $hashResponse = $snmpSession->get_request(-varbindlist => [$oid]);
        my $response = "$hashResponse->{$oid}";
        
        if (exists $doNotSumValues{$type} && !defined $doNotSumValues {$type}) {
            $ret .= " $response";
        } else {
            $ret += $response;
        }
    }
    
    if (exists $doNotSumValues{$type} && !defined $doNotSumValues{$type}) {
        $msg = "$type: OK - $ret";
    } else {
        if (alertByRange($crit, $ret) == 1) {
            $stat = 2;
            $msg = "$type: Crit - $ret";
        } elsif (alertByRange($warn, $ret) == 1) {
            $stat = 1;
            $msg = "$type: WARN - $ret";
        } else {
            $stat = 0;
            $msg = "$type: OK - $ret";
        }
    }
    
} elsif ($type eq "mem" || $type eq "disk") {

    my $oid = $oids{"$type"."Used"};
    my $hashResponse = $snmpSession->get_request(-varbindlist => [$oid]);
    my $used = "$hashResponse->{$oid}";
    
    if ($used eq '' || $used eq 'n/a' || $used eq 'noSuchInstance'){
        exitUnknown("$type not supported, response", $used);
    }
    
    $oid = $oids{"$type"."Total"};
    $hashResponse = $snmpSession->get_request(-varbindlist => [$oid]);
    my $total = "$hashResponse->{$oid}";
    
    my $free = $total - $used;

    $used = int($used / 1024 / 1024);
    $free = int($free / 1024 / 1024);
    $total = int($total / 1024 / 1024);

    my $freePercent = int($free / $total * 100);
    
    if (alertByRange($crit, $freePercent) == 1) {
        $stat = 2;
        $msg = "$type: CRIT - ";
    } elsif (alertByRange($warn, $freePercent) == 1) {
        $stat = 1;
        $msg = "$type: WARN - ";
    } else {
        $stat = 0;
        $msg = "$type: OK - ";
    }
    
    $msg .= "$type free: $freePercent%";
    $perf = "total=$total"."MB"."used=$used"."MB";
    
} else {

    my $oid = "$oids{$type}";
    my $hashResponse = $snmpSession->get_request(-varbindlist => [$oid]);
    my $response = "$hashResponse->{$oid}";

    if ($response eq '' || $response eq 'n/a' || $response eq 'noSuchInstance'){
        exitUnknown("$type not supported, response", $response);
    } else {
    
        if ($type eq "voltage" || index($type, 'emperature') != -1 || index($type, 'current') != -1 ) {
            $response /= 10;
        }
        
        if (alertByRange($crit, $response) == 1) {
            $stat = 2;
            $msg = "$type: CRIT - ";
        } elsif (alertByRange($warn, $response) == 1) {
            $stat = 1;
            $msg = "$type: WARN - ";
        } else {
            $stat = 0;
            $msg = "$type: OK - ";
        }
        
        $perf = "$type=$response";
    }

    if (index($type, 'emperature') != -1) {
        $response .= "°C";
    } elsif ($type eq 'cpu') {
        $response .= "%";
    } elsif ($type eq 'voltage') {
        $response .= "V";
    }
    $msg .= $response;
    $perf = "$type=$response";
}

$snmpSession->close;

print "$msg | $perf\n";

exit $stat;
