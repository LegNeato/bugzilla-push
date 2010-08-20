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
# The Original Code is the AMQP Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Christian Legnitto <clegnitto@mozilla.com>

package Bugzilla::Extension::AMQP;

use strict;
use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util;
use base qw(Bugzilla::Extension);

# Dependencies
use Scalar::Util;
use Net::RabbitFoot;
use JSON qw(-convert_blessed_universally);

# Use our lib
use Bugzilla::Extension::AMQP::Util;

our $VERSION = '0.01';

# Override this hook to get configuration options in the Admin section
sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{'panel_modules'};
    $modules->{'AMQP'} = 'Bugzilla::Extension::AMQP::Params';
}

# Call our wrapper every time an object is created
sub object_end_of_create {
    my ($self, $args) = @_;
    $self->_wrap('object_end_of_create', $args);
}

# Call our wrapper every time an object is updated
sub object_end_of_update {
    my ($self, $args) = @_;

    # These object types are handled by their respective subs
    # If we handled them at the object level we would get
    # duplicate messages
    if( $args->{'object'}->isa('Bugzilla::Bug') || 
        $args->{'object'}->isa('Bugzilla::Group') ||
        $args->{'object'}->isa('Bugzilla::Flag') ) {
        return;
    }

    # Everything else we want to process at the object level
    $self->_wrap('object_end_of_update', $args);
}

# Call our wrapper every time a bug is updated
# (this is needed as not every change is caught by the object hook)
sub bug_end_of_update {
    my ($self, $args) = @_;
    $self->_wrap('object_end_of_update', $args);
}

# Call our wrapper every time a flag is updated
# (this is needed as not every change is caught by the object hook)
sub flag_end_of_update {
    my ($self, $args) = @_;
    $self->_wrap('object_end_of_update', $args);
}

# Call our wrapper every time a group is updated
# (this is needed as not every change is caught by the object hook)
sub group_end_of_update {
    my ($self, $args) = @_;
    $self->_wrap('object_end_of_update', $args);
}

# Wrapper makes it so we can choose if message send failures are fatal or not
sub _wrap {
    my ($self, $func, $args) = @_;
    my $priv_func = "_$func";
    eval { $self->$priv_func($args); };
    if( $@ && Bugzilla->params->{'AMQP-fail-on-error'} ) {
        warn "AMQP: Error while sending message: ", $func, ": ", $@;
        $@ =~ s/\s+at .*$//;
        ThrowCodeError($@);
    }
}

sub _object_end_of_create {
    my ($self, $args) = @_;
    $self->_send('object-created', $args);
}

sub _object_end_of_update {
    my ($self, $args) = @_;
    $self->_send('object-modified', $args);
}

sub _send {
    my ($self, $msgtype, $args) = @_;

    my $object     = $args->{'object'} || 
                     $args->{'bug'} ||
                     $args->{'flag'} ||
                     $args->{'group'}; 

    my $old_object = $args->{'old_object'} ||
                     $args->{'old_bug'} ||
                     $args->{'old_flag'} ||
                     $args->{'old_group'};

    my $changes    = $args->{'changes'} || {};

    # We get called on user objects even when there are no changes
    if( $msgtype eq 'object-modified' ) {
        unless( $changes && %$changes ) {
            return;
        }
    }

    my $class = Scalar::Util::blessed($object);

    # Search objects are not interesting and would slow down performance
    if( $class =~ /Search/g ) {
        return;
    }

    # Flag values set on bugs show up as "created", we want to send "modified"
    # messages instead
    if( $msgtype eq 'object-created' && $class eq "Bugzilla::Flag") {
        my $changes = {
            # We use flagtype.name as that's what's used by bugzilla once a
            # flag is attached to a bug and changes
            'flagtype.name' => ['',$object->{'name'}]
        };
        $self->_object_end_of_update($object->bug(), $changes);
        return;
    }

    # Make sure we have settings we need
    $self->verify_publish_settings($msgtype);

    # Find the "type" of object (simple lower-case string)
    my $type = lc $class;
    $type =~ s/^bugzilla::([^:]+).*$/$1/g;

    # Process the exchange the user wants to use
    my $exchange = Bugzilla->params->{'AMQP-'.$msgtype.'-exchange'};
    $exchange =~ s/%type%/$type/g;

    # Process the vhost the user wants to use
    my $vhost = Bugzilla->params->{'AMQP-'.$msgtype.'-vhost'};
    $vhost =~ s/%type%/$type/g;

    # Set up the json encoder
    my $json = JSON->new->utf8;
    $json->allow_nonref(1);
    $json->allow_blessed(1);
    $json->convert_blessed(1);
    $json->shrink(1);

    # This prepares the object so JSON doesn't choke. It is also where
    # translation will happen to keep a stable API
    my $prepped_object = prep_object($object);

    # Connect to the broker
    my $amqp = $self->broker_connect();

    # Open a channel
    my $ch = $amqp->open_channel();

    # Get a timestamp to include in the message
    my $timestamp = Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    
    # Do this if we are creating a message for a new object
    if( $msgtype eq 'object-created' ) {

        # Process the routing key the user wants to use
        my $routingkey = Bugzilla->params->{'AMQP-object-created-routingkey'};
        $routingkey =~ s/%type%/$type/g;

        # Create the message in the proper format
        my $msg = $self->msg_envelope($routingkey,
                                      $timestamp,
                                      $type,
                                      $prepped_object,
        );

        # Send the message
        $self->publish_message($ch,
                               $exchange,
                               $vhost,
                               $routingkey,
                               $json->encode($msg), 
                               { content_type => 'application/json' },
        );
    }

    # Do this if we are creating a message for a changed object
    if( $msgtype eq 'object-modified' ) {
    
        # Send individual messages for each change
        foreach my $changed_field (keys %$changes) {

            # Handle this one special
            my $replacement = $changed_field;
            if( $changed_field eq "flagtypes.name" ) {
                # This is sort of a hack to make data nice
                $replacement = 'flag.';
                # Look for a value that isn't empty
                foreach my $val (@{$changes->{'flagtypes.name'}}) {
                    if( $val ) {
                        # We have a value, subtract the -, +, or ?(user)
                        #  off the end to get the field name
                        $val =~ s/^([^?+-]+)[?+-].*$/$1/;
                        $replacement .= $val;
                        last;
                    }
                }
            }

            # Get field name mappings
            my $mappings = {};
            if( $class eq "Bugzilla::Bug" ) {
                $mappings = bug_reverse_interface();
            }elsif( $class eq "Bugzilla::Product" ) {
                $mappings = product_reverse_interface();
            }elsif( $class eq "Bugzilla::Status" ) {
                $mappings = status_reverse_interface();
            }elsif( $class eq "Bugzilla::Flag" ) {
                $mappings = flag_reverse_interface();
            }elsif( $class eq "Bugzilla::FlagType" ) {
                $mappings = flagtype_reverse_interface();
            }elsif( $class eq "Bugzilla::Keyword" ) {
                $mappings = keyword_reverse_interface();
            }elsif( $class eq "Bugzilla::Attachment" ) {
                $mappings = attachment_reverse_interface();
            }elsif( $class eq "Bugzilla::Milestone" ) {
                $mappings = milestone_reverse_interface();
            }elsif( $class eq "Bugzilla::Version" ) {
                $mappings = version_reverse_interface();
            }

            # Map if we need to
            if( $mappings && $mappings->{$replacement} ) {
                $replacement = $mappings->{$replacement};
            }

            # Process the routing key the user wants to use
            my $routingkey = Bugzilla->params->{'AMQP-object-data-changed-routingkey'};
            $routingkey =~ s/%type%/$type/g;
            $routingkey =~ s/%field%/$replacement/g;

            # Process the vhost further so we can put the field in it
            $vhost =~ s/%field%/$replacement/g;

            # Create the message in the proper format
            my $msg = $self->msg_envelope($routingkey,
                                          $timestamp,
                                          $type,
                                          $prepped_object,
                                          $changes->{$changed_field}
            );

            # Send the message
            $self->publish_message($ch,
                                   $exchange,
                                   $vhost,
                                   $routingkey,
                                   $json->encode($msg), 
                                  { content_type => 'application/json' },
            );
        }
    }

    # Don't need to close here as it causes an error and the connection will
    # be torn down at execution end anyway
    #$ch->close();
}

# Function to connect to the broker. We only connect once as both
# Net::RabbitFoot (which we are using) and Net::AMQP::Simple (which we were
# using before) fail miserably if we connect and disconnect in the same
# script execution
sub broker_connect {
    my ($self) = @_;

    # If we have already connected, return the connection
    if( $self->{'amqp_conn'} ) {
        return $self->{'amqp_conn'};
    }

    # Make sure we have the values to connect
    my @param_names = (
        'AMQP-hostname',
        'AMQP-port',
        'AMQP-username',
        'AMQP-password',
    );
    foreach my $param (@param_names) {
        if( !Bugzilla->params->{$param} ) {
            die "missing-$param";
        }
    }

    # Make our RabbitFoot connection object
    $self->{'amqp_conn'} = Net::RabbitFoot->new();

    # Load in the AMQP configuration
    my $spec = Bugzilla->params->{'AMQP-spec-xml-path'} ||
                     $self->{'amqp_conn'}->default_amqp_spec();

    $self->{'amqp_conn'}->load_xml_spec($spec);

    # Connect to the broker
    $self->{'amqp_conn'}->connect(
        host    => Bugzilla->params->{'AMQP-hostname'},
        port    => Bugzilla->params->{'AMQP-port'},
        user    => Bugzilla->params->{'AMQP-username'},
        pass    => Bugzilla->params->{'AMQP-password'},
        # TODO: Move this/do something useful with the vhost
        vhost   => '/',
        timeout => 1,
    );

    # Return our connected object
    return $self->{'amqp_conn'};

}

# Check config settings needed to publish, bail if they aren't there
sub verify_publish_settings {
    my ($self, $pubtype) = @_;

    die "missing-AMQP-".$pubtype."-exchange" unless
         Bugzilla->params->{'AMQP-'.$pubtype.'-exchange'};

    die "missing-AMQP-".$pubtype."-vhost" unless
         Bugzilla->params->{'AMQP-'.$pubtype.'-vhost'};
}

# Creates a message in the proper format
sub msg_envelope {
    my ($self, $routingkey, $timestamp, $type, $data, $changedata) = @_;

    my $message = {};
    
    # Meta section
    $message->{'_meta'} = {
        routing_key => $routingkey,
        time        => Bugzilla::Util::datetime_from($timestamp,'UTC') . '',
    };

    # Payload section
    $message->{'payload'} = {
        $type => $data,
    };

    # Add changes if we have any
    if( $changedata ) {
        $message->{'payload'}->{'change'} = $changedata;
    }

    return $message;
}

# Actually sends the desired message
sub publish_message {
    my ($self, $ch, $exchange, $vhost, $routingkey, $data, $headers) = @_;

    # TODO: Support configurable exchange types
    $ch->declare_exchange(
            exchange => $exchange,
            type     => 'topic',
            durable  => 1,
            vhost    => $vhost,
    );

    # Actually send the message via AMQP
    $ch->publish(
            exchange    => $exchange,
            vhost       => $vhost,
            routing_key => $routingkey,
            body        => $data,
            header      => $headers,
    );
}


__PACKAGE__->NAME;
