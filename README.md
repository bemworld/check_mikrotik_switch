# check_mikrotik_switch.pl

## Overview

This is a simple check script for Nagios/Icinga to monitor switches from MikroTik.

It is tested with CRS125-24G-1S and CRS226-24G-2S switches. 

Due to the lack of other hardware i couldn't test some features, e.g. memory and disk.

## Author
 Bernd Klier bem -(at)- bemworld.de
 
## Installation

In your Nagios plugins directory run

<pre><code>git clone git@github.com:bemworld/check_mikrotik_switch.git</code></pre>

## Usage


         
	Parameters:
        -H <ip-address>     The IP address or the host name of the switch
        [-C <community>]    The SNMP community string (default: public) [optional]
        -t <test type>      The test type to execute. See below.
        -i <switch ports>   single, multiple and ranges possible, for example: 1,5-10,22-24
        -w <warn range>     Range for result WARNING, standard nagios threshhold format
        -c <crit range>     Range for result CRITICAL, standard nagios threshhold format
        
        
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

### Install in Nagios

Create commands, e.g.

<pre><code>
define command {
        command_name                    check_mt_voltage
        command_line                    $USER1$/check_mikrotik_switch.pl -H $HOSTADDRESS$ -C public -t voltage -w $ARG1$ -c $ARG2$
}

define command {
        command_name                    check_mt_cpu
        command_line                    $USER1$/check_mikrotik_switch.pl -H $HOSTADDRESS$ -C public -t cpu -w $ARG1$ -c $ARG2$
}

define command {
        command_name                    check_mt_temp
        command_line                    $USER1$/check_mikrotik_switch.pl -H $HOSTADDRESS$ -C public -t temperature -w $ARG1$ -c $ARG2$
}

define command {
        command_name                    check_mt_port_sum
        command_line                    $USER1$/check_mikrotik_switch.pl -H $HOSTADDRESS$ -C public -t $ARG1$ -i $ARG2$ -w $ARG3$ -c $ARG4$
}

define command {
        command_name                    check_mt_port_info
        command_line                    $USER1$/check_mikrotik_switch.pl -H $HOSTADDRESS$ -C public -t $ARG1$ -i $ARG2$
}

</code></pre>


### Service samples

#### Check Voltage

This will check each host that is listed in the MikroTik Switches group. It will issue a warning if the voltage is below 23V or above 26V and a critical error if it is below 22V or above 27V

<pre><code>
define service {
        use                     generic-service
        hostgroup_name          MikroTik Switches
        service_description     MikroTik Voltage
        check_command           check_mt_voltage!23:26!22:27
}
</code></pre>

#### Check TX Errors

This test adds up all tx-errors on ports 1-25 (all ports on a CRS125-24G-1S). 

<pre><code>
define service {
        use                     generic-service
        hostgroup_name          MikroTik Switches
        service_description     MikroTik TX Errors
        check_command           check_mt_port_sum!portTxErrors!1-25!10!50
}
</code></pre>

#### Port Names

This test returns the port names of ports 1, 3, 4, 5 and 25
<pre><code>
define service {
        use                     generic-service
        hostgroup_name          MikroTik Switches
        service_description     MikroTik Port Names
        check_command           check_mt_port_info!portName!1,3-5,25
}
</code></pre>
