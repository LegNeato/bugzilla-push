# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Push Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Christian Legnitto <clegnitto@mozilla.com>

package Bugzilla::Extension::Push::Backend::STOMP;

use strict;

use Net::Stomp;

sub new {
    my ($class, $spec_path) = @_;

    # Create our empty object
    my $self = {};

    # Make the object a STOMP backend object
    bless $self, $class;

    return $self;
}

sub can_connect {
    my ($self, $specified) = @_;

    $specified ||= {};

    # Make sure we have the values to connect

    my @param_names = (
        'hostname',
        'username',
        'password',
    );
    foreach my $param (@param_names) {
        die "missing-$param" unless $specified->{$param};
    }
}

sub connect {
    my ($self, $params) = @_;

    # Make sure we can connect
    $self->can_connect($params);

    # Start out with a fresh connection
    if( $self->{'stomp_conn'} ) {
        $self->{'stomp_conn'}->disconnect();
        delete $self->{'stomp_conn'};
    }

    # Set up the STOMP object
    $self->{'stomp_conn'} = new Net::Stomp({
        hostname    => $params->{'hostname'},
        port        => $params->{'port'} || 61613,
        ssl         => $params->{'ssl'} || 0,
        ssl_options => $params->{'ssl_options'} || {}
    });

    # Connect to the broker
    $self->{'stomp_conn'}->connect({
        login    => $params->{'username'},
        passcode => $params->{'password'},
    });

}

sub can_publish {
    my ($self, $specified) = @_;

    $specified ||= {};

    # Make sure we have the values to connect

    my @param_names = (
        'exchange',
        'vhost',
        'routing_key',
    );
    foreach my $param (@param_names) {
        die "missing-$param" unless $specified->{$param};
    }
}

sub publish {
    my ($self, $params) = @_;

    $params ||= {};

    # Make sure we can publish and set vars
    $self->can_publish($params);

    # Message can be empty
    $params->{'message'} ||= '';

    # Fill out STOMP-specific headers
    $params->{'headers'} ||= {};
    $params->{'headers'}->{'exchange'}    = $params->{'exchange'};
    $params->{'headers'}->{'vhost'}       = $params->{'vhost'};
    $params->{'headers'}->{'destination'} = $params->{'routing_key'};
    # Needed for ActiveMQ
    $params->{'headers'}->{'persistent'}  = 'true';

    # Set the content-length so STOMP control chars don't stop processing
    use bytes;
    $params->{'headers'}->{'content-length'} = length($params->{'message'});

    # Make a custom STOMP frame
    my $frame = new Net::Stomp::Frame({
        command     => 'SEND',
        body        => $params->{'message'},
        headers     => $params->{'headers'},
    });

    # Actually send the message via STOMP
    # TODO: There is no send_frame_transaction?
    $self->{'stomp_conn'}->send_frame($frame);
}

sub disconnect {
    my $self = shift;
    # This hangs bugzilla...
    #$self->{'stomp_conn'}->disconnect() if $self->{'stomp_conn'};
}

1;
