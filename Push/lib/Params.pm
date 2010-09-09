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

package Bugzilla::Extension::Push::Params;

use strict;

use Bugzilla::Config::Common;
use Bugzilla::Util;

our $sortkey = 1250;

sub check_push_protocol {
    my $option = shift;

    if( $option eq 'AMQP' ) {
        if( !Bugzilla->feature('push_amqp') ) {
            return "AMQP support is not available. Run checksetup.pl " .
                   "for more details";
        }
    }

    if( $option eq 'STOMP' ) {
        if( !Bugzilla->feature('push_stomp') ) {
            return "STOMP support is not available. Run checksetup.pl " .
                   "for more details";
        }
    }

    return "";
}

use constant get_param_list => (
  {
   name => 'push-protocol',
   type => 's',
   choices => [ '', 'AMQP', 'STOMP' ],
   default => '',
   checker => \&check_push_protocol
  },

  {
   name => 'push-hostname',
   type => 't',
   default => ''
  },

  {
   name => 'push-port',
   type => 't',
   default => ''
  },

  {
   name => 'push-username',
   type => 't',
   default => ''
  },
  {
   name => 'push-password',
   type => 'p',
   default => ''
  },
  {
   name => 'AMQP-spec-xml-path',
   type => 't',
   default => ''
  },
  {
   name => 'push-object-created-exchange',
   type => 't',
   default => ''
  },
  {
   name => 'push-object-created-vhost',
   type => 't',
   default => '/'
  },
  {
   name => 'push-object-created-routingkey',
   type => 't',
   default => '%type%.new'
  },
  {
   name => 'push-object-modified-exchange',
   type => 't',
   default => ''
  },
  {
   name => 'push-object-modified-vhost',
   type => 't',
   default => '/'
  },
  {
   name => 'push-object-data-changed-routingkey',
   type => 't',
   default => '%type%.changed.%field%'
  },
# TODO: Differentiate between data that has changed, been added, or been removed
#  {
#   name => 'push-object-data-added-routingkey',
#   type => 't',
#   default => "%type%.added.%field%"
#  },
#  {
#   name => 'push-object-data-removed-routingkey',
#   type => 't',
#   default => "%type%.removed.%field%"
#  },
  {
   name => 'push-fail-on-error',
   type => 'b',
   default => 1
  },
  {
   name => 'push-publish-restricted-messages',
   type => 'b',
   default => 0
  },
);

1;
