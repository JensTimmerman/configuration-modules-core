# ${license-info}
# ${developer-info}
# ${author-info}


declaration template components/nfs/schema;

include 'quattor/types/component';

type structure_nfs_exports = {
    'path' : string
    'hosts' : string{}
};

type structure_nfs_mounts = {
    'device' : string
    'mountpoint' : string
    'fstype' : string with match(SELF, '^(nfs4?|(pan|ceph)fs|none)$')
    'options' ? string
    'freq' ? long(0..)
    'passno' ? long(0..)
};

type component_nfs = {
    include structure_component
    'exports' ? structure_nfs_exports[]
    'mounts' ? structure_nfs_mounts[]
};
