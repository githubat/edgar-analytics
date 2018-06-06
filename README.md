
This is my 2018 Code Challenge Solution in Perl 

Data Structure

Extensive global variables used, and all IP entries are store in hash table ip_tab;

ip_tab[][ ftm ]   = time stamp when the IP entry is added

ip_tab[][ ltm ]  = time stamp when the IP entry is updated (new document access)

ip_tab[][ sno ]  = serial number

ip_tab[][ dcnt]  = viewed document counter

ip_tab[][tocnt]= timeout counter (space vs time to avoid massive time difference calculation each round in invalidate_ip_tab)

The code should run with standard default Perl installation as I have ported the time conversion function to become subroutines with the code.

At least it ran through a big csv file without crashing :-)~

Clearly understood that "Perl" is not listed as a "primary programming language" in the instruction.

So, if this submition is DOA, I am at peace with that deciosion.

Thanks much for the oppourtunity and your time on this submission!
