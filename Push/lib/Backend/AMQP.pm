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

package Bugzilla::Extension::Push::Backend::AMQP;

use strict;

use Net::RabbitFoot;

sub new {
    my ($class, $spec_path) = @_;

    # Create our empty object
    my $self = {};

    # Make our RabbitFoot connection object
    $self->{'amqp_conn'} = Net::RabbitFoot->new();

    # Load in the AMQP configuration
    $spec_path ||= $self->{'amqp_conn'}->default_amqp_spec();

    $self->{'amqp_conn'}->load_xml_spec($spec_path);

    # Make the object an AMQP backend object
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

    $self->{'amqp_conn'}->close() if $self->{'amqp_conn'};

    # Connect to the broker
    $self->{'amqp_conn'}->connect(
        host    => $params->{'hostname'},
        port    => $params->{'port'} || 5672,
        user    => $params->{'username'},
        pass    => $params->{'password'},
        # TODO: Move this/do something useful with the vhost
        vhost   => $params->{'vhost'}   || '/',
        timeout => $params->{'timeout'} || 1,
    );
}

sub can_publish {
    my ($self, $specified) = @_;

    $specified ||= {};

    # Make sure we have the values to publish

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

    # Make sure we can publish
    $self->can_publish($params);

    # Set up the headers
    $params->{'headers'} ||= {};
    # RabbitFoot needs this translated
    $params->{'headers'}->{'content_type'} = $params->{'headers'}->{'content-type'};
    delete $params->{'headers'}->{'content-type'};

    # user_id header has to be set to the authenticated user
    # otherwise rabbitmq refuses connection with
    # user_id property set to '' but authenticated user was 'bugzilla'
    $params->{'headers'}->{'user_id'} = $params->{'username'};

    # Get a channel to publish to
    $self->{'channel'} = $self->{'amqp_conn'}->open_channel();

    $self->{'channel'}->declare_exchange(
            # These are required to be specified
            exchange => $params->{'exchange'},
            vhost    => $params->{'vhost'},
            type     => $params->{'exchange_type'}      || 'topic',
            durable  => $params->{'exchange_isdurable'} || 1
    );

    # Actually send the message via AMQP
    $self->{'channel'}->publish(
            exchange    => $params->{'exchange'},
            vhost       => $params->{'vhost'},
            routing_key => $params->{'routing_key'},
            body        => $params->{'message'} || '',
            header      => $params->{'headers'}
    );

    $self->{'channel'}->close();
    delete $self->{'channel'};
}

sub disconnect {
    my $self = shift;
    $self->{'amqp_conn'}->close();
}

1;
