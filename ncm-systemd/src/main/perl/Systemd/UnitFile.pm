#${PMpre} NCM::Component::Systemd::UnitFile${PMpost}

use 5.10.1;

use parent qw(CAF::Object Exporter CAF::Path);

use Scalar::Util qw(blessed);

use CAF::Object qw (SUCCESS);

use Readonly;

use EDG::WP4::CCM::TextRender 17.2.1;
use NCM::Component::Systemd::Systemctl qw(systemctl_daemon_reload);

Readonly my $UNITFILE_DIRECTORY => '/etc/systemd/system';
Readonly my $NOREPLACE_FILENAME => 'quattor.conf';

Readonly my $UNITFILE_TT => 'unitfile';

Readonly::Hash our %CUSTOM_ATTRIBUTES => {
    CPUAffinity => '_hwloc_calc_cpuaffinity',
};

Readonly::Array my @HWLOC_CALC_CPUS => qw(hwloc-calc --physical-output --intersect PU);

=pod

=head1 NAME

NCM::Component::Systemd::UnitFile handles the configuration of C<ncm-systemd> unitfiles.

=head2 Public methods

=over

=item new

Returns a new object, accepts the following mandatory arguments

=over

=item unit

The unit (full C<name.type>).

=item config

A C<EDG::WP4::CCM::CacheManager::Element> instance with the unitfile configuration.

(An element instance is required becasue the rendering of
the configuration is pan-basetype sensistive).

=back

and options

=over

=item replace

A boolean to replace the configuration. (Default/undef is false).

For a non-replaced configuration, a directory
C<</etc/systemd/system/<unit>.d>> is created
and the unitfile is C<</etc/systemd/system/<unit>.d/quattor.conf>>.
Systemd will pickup settings from this C<quattor.conf> and other C<.conf> files
in this directory,
and also any configuration for the unit in the default systemd paths (e.g. typical
unit part of the software package located in
C<</lib/systemd/system/<unit>>>).

A replaced configuration overrides all existing system unitfiles
for the unit (and has to define all attributes). It has filename
C<</etc/systemd/system/<unit>>>.

=item backup

Backup files and/or directories.

=item custom

A hashref with custom configuration data. See C<custom> method.

=item log

A logger instance (compatible with C<CAF::Object>).

=back

=cut

sub _initialize
{
    my ($self, $unit, $el, %opts) = @_;

    $self->{unit} = $unit;
    $self->{config} = $el;

    $self->{replace} = $opts{replace} ? 1 : 0; # replace 0 / 1
    $self->{backup} = $opts{backup} if $opts{backup};

    $self->{custom} = $opts{custom} if $opts{custom};
    $self->{log} = $opts{log} if $opts{log};

    return SUCCESS;
}

=item custom

The C<custom> method prepares configuration data that is cannot be
found in the profile.

Report hashref with custom data on success, undef otherwise.

Following custom attributes are supported:

=over

=item CPUAffinity

Obtain the C<systemd.exec> C<CPUAffinity> list determined via C<hwloc(7)> locations.

Allows to e.g. cpubind on numanodes using the C<node:X> location

Forces an empty list to reset any possible previously defined affinity.

=back

=cut

sub custom
{
    my ($self) = @_;

    my $res = {};

    foreach my $attr (keys %{$self->{custom}}) {
        my $method = $CUSTOM_ATTRIBUTES{$attr};
        if ($method) {
            # the existence is unittested
            if($self->can($method)) {
                my $value = $self->$method($self->{custom}->{$attr});
                if (defined($value)) {
                    $res->{$attr} = $value;
                } else {
                    $self->error("Method $method for custom attribute $attr failed.");
                    return;
                }
            } else {
                $self->error("Unsupported method $method for custom attribute $attr.");
                return;
            }
        } else {
            $self->error("Unsupported custom attribute $attr.");
            return;
        }
    }

    return $res;
}

=item write

Create the unitfile. Returns undef in case of problem,
a boolean indication if something changed otherwise.

(This method will take all required actions to use the values, like
reloading the systemd daemon.
It will not however change the state of the unit,
e.g. by restarting it.)

=cut

sub write
{
    my ($self) = @_;

    if (!(blessed($self->{config}) &&
           $self->{config}->isa("EDG::WP4::CCM::CacheManager::Element"))) {
        $self->error("config has to be an Element instance");
        return;
    }

    # custom values
    my $custom = $self->custom();
    return if (! defined($custom));

    # prepare/cleanup destination and return filename
    my $filename = $self->_prepare_path($UNITFILE_DIRECTORY);
    return if(! defined($filename));

    # render
    my $trd = EDG::WP4::CCM::TextRender->new(
        $UNITFILE_TT,
        $self->{config},
        relpath => 'systemd',
        log => $self,
        ttoptions => _make_variables_custom($custom),
        );

    # write
    my $fh = $trd->filewriter(
        $filename,
        backup => $self->{backup},
        mode => oct(664),
        log => $self,
        );

    if(! defined($fh)) {
        $self->error("Rendering unitfile for unit $self->{unit}",
                     " (filename $filename) failed: $trd->{fail}.");
        return;
    }

    my $changed = $fh->close() ? 1 : 0; # force to 1 or 0

    # if changed, reload daemon
    if ($changed) {
        # can't do much with return value?
        systemctl_daemon_reload($self);
    }

    return $changed;
}

=pod

=back

=head2 Private methods

=over

=item _prepare_path

Create and return the filename to use,
and prepare the directory structure if needed.

C<basedir> is the base directory to use, e.g. C<$UNITFILE_DIRECTORY>.

=cut

sub _prepare_path
{
    my ($self, $basedir) = @_;

    my $filename;

    my $unitfile = "$basedir/$self->{unit}";
    my $unitdir = "${unitfile}.d";

    if ($self->{replace}) {
        # unitdir can't exist
        return if (! $self->cleanup($unitdir));

        $filename = $unitfile;
    } else {
        # unitfile can't exist
        return if (! $self->cleanup($unitfile));

        $filename = "$unitdir/$NOREPLACE_FILENAME";
        if (! $self->directory($unitdir)) {
            $self->error("Failed to create unitdir $unitdir: $self->{fail}");
            return;
        }
    };

    return $filename;
}

=item _hwloc_calc_cpuaffinity

Run C<_hwloc_calc_cpus>, and returns in C<CPUAffinity> format with a reset

=cut

sub _hwloc_calc_cpuaffinity
{
    my ($self, $locations) = @_;

    my $cpus = $self->_hwloc_calc_cpus($locations);
    return if(! defined($cpus));

    # first empty list, to reset all previous defined CPUaffinity settings
    return [[], $cpus];
}


=item _hwloc_calc_cpus

Run the C<hwloc-calc --physical --intersect PU> command for C<locations>.

Returns arrayref with CPU indices on success, undef otherwise.

=cut

sub _hwloc_calc_cpus
{
    my ($self, $locations) = @_;

    # pass a copy of the Readonly array, so we can extend it
    my $proc = CAF::Process->new([@HWLOC_CALC_CPUS], log => $self);
    $proc->pushargs(@$locations);

    my @indices;
    my @unexpected;
    my $output = $proc->output();
    foreach my $line (split("\n", $output)) {
        if($line =~ m/^\d+(,\d+)*$/) {
            @indices = split(/,/, $line);
        } else {
            push(@unexpected, $line) if $line;
        }
    }

    if(@unexpected) {
        $self->warn("Unexpected output from $proc: ", join("\n", @unexpected));
    }

    if (@indices) {
        return \@indices;
    } else {
        $self->error("No indices from from $proc: $output");
        return;
    }
}


=item _make_variables_custom

A function that return the custom variables hashref to pass as ttoptions.
(This is a function, not a method).

=cut

sub _make_variables_custom {
    my $customs = shift;
    my $ttoptions;
    $ttoptions->{VARIABLES}->{SYSTEMD}->{CUSTOM} = $customs;
    return $ttoptions;
}

=pod

=back

=cut

1;
