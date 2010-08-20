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

package Bugzilla::Extension::AMQP::Params;

use strict;

use Bugzilla::Config::Common;
use Bugzilla::Util;

our $sortkey = 1250;

use constant get_param_list => (
  {
   name => 'AMQP-hostname',
   type => 't',
   default => ''
  },

  {
   name => 'AMQP-port',
   type => 't',
   default => '5672'
  },

  {
   name => 'AMQP-username',
   type => 't',
   default => ''
  },
  {
   name => 'AMQP-password',
   type => 'p',
   default => ''
  },
  {
   name => 'AMQP-spec-xml-path',
   type => 't',
   default => ''
  },
  {
   name => 'AMQP-object-created-exchange',
   type => 't',
   default => ''
  },
  {
   name => 'AMQP-object-created-vhost',
   type => 't',
   default => '/'
  },
  {
   name => 'AMQP-object-created-routingkey',
   type => 't',
   default => "%type%.new"
  },
  {
   name => 'AMQP-object-modified-exchange',
   type => 't',
   default => ''
  },
  {
   name => 'AMQP-object-modified-vhost',
   type => 't',
   default => '/'
  },
  {
   name => 'AMQP-object-data-changed-routingkey',
   type => 't',
   default => "%type%.changed.%field%"
  },
# TODO: Differentiate between data that has changed, been added, or been removed
#  {
#   name => 'AMQP-object-data-added-routingkey',
#   type => 't',
#   default => "%type%.added.%field%"
#  },
#  {
#   name => 'AMQP-object-data-removed-routingkey',
#   type => 't',
#   default => "%type%.removed.%field%"
#  },
  {
   name => 'AMQP-fail-on-error',
   type => 'b',
   default => 1
  },
# TODO: Figure out a way to tell if a bug is viewable by the public
#  {
#   name => 'AMQP-publish-restricted-bugs',
#   type => 'b',
#   default => 0
#  },
);

1;
