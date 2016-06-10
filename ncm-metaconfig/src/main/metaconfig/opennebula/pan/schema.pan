declaration template metaconfig/opennebula/schema;

include 'pan/types';

@documentation{
aii/opennebula.conf sections.
port: port used to connect to the RPC endpoint (2633 by default)
pattern: a valid regular expression to match a VM fqdn. 
If the VM fqdn match the pattern the aii will use this section 
instead of [VM_DOMAIN].
The search proceeds through patterns from start to end, 
stopping at the first match found, if not [VM_DOMAIN] is used instead.
And finally if [VM_DOMAIN] does not exist the aii will use [rpc] default section.
}
type aii_section = {
    "password" : string
    "host" : string
    "port" ? long
    "user" ? string
    "pattern" ? string
} = dict();

@documentation{
aii/opennebula.conf sections
This is a dictionary (to generate a section per rpc endpoint)
of dictionaries (to include the endpoint options)
}
type aii_opennebula_conf = aii_section{};
