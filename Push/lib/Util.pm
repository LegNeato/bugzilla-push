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

package Bugzilla::Extension::Push::Util;
use strict;
use Bugzilla::Util;
use JSON;

use base qw(Exporter);

our @EXPORT = qw(
    prep_object    

    bug_interface
    bug_reverse_interface

    user_interface
    user_reverse_interface

    status_interface
    status_reverse_interface
    
    attachment_interface
    attachment_reverse_interface
    
    product_interface
    product_reverse_interface

    milestone_interface
    milestone_reverse_interface

    version_interface
    version_reverse_interface

    keyword_interface
    keyword_reverse_interface

    flag_interface
    flag_reverse_interface

    flagtype_interface
    flagtype_reverse_interface

    comment_interface
    comment_reverse_interface
    
);

# TODO: If I could figure out a general way to call functions with variable
# names this file would be a lot smaller and less hardcoded

# Takes an object and tries to prepare it for JSON output
# TODO: Limit recursion depth to 3 or so
sub prep_object {
    my $object = shift;
    my $data = {};

    my $mappings;

    # Undef if we get something unexpected
    return undef unless $object && ref($object);

    # Whenever you add an interface here make sure the functions are in this
    # file and make sure you add it to _send() in Extension.pm as well
    if( $object->isa('Bugzilla::Bug') ) {
        $mappings = bug_interface();
    }elsif( $object->isa('Bugzilla::User') ) {
        $mappings = user_interface();
    }elsif( $object->isa('Bugzilla::Comment') ) {
        $mappings = comment_interface();
    }elsif( $object->isa('Bugzilla::Product') ) {
        $mappings = product_interface();
    }elsif( $object->isa('Bugzilla::Status') ) {
        $mappings = status_interface();
    }elsif( $object->isa('Bugzilla::Attachment') ) {
        $mappings = attachment_interface();
    }elsif( $object->isa('Bugzilla::Milestone') ) {
        $mappings = milestone_interface();
    }elsif( $object->isa('Bugzilla::Version') ) {
        $mappings = version_interface();
    }elsif( $object->isa('Bugzilla::Keyword') ) {
        $mappings = keyword_interface();
    }elsif( $object->isa('Bugzilla::Flag') ) {
        $mappings = flag_interface();
    }elsif( $object->isa('Bugzilla::FlagType') ) {
        $mappings = flagtype_interface();
    }else {
        # By default we'll return the object and hope JSON can deal with it
        $data = $object;
    }

    if( $mappings ) {

        # Add support for custom fields
        # TODO: Look up custom field type and act smarter
        foreach my $thefield (keys %$object) {
            if( $thefield =~ /^cf_/ ) {
                $mappings->{$thefield} = {
                    action => 'none',
                    from   => $thefield,
                };
            }
        }

        # Loop through the mappings
        foreach my $to_field (keys %$mappings) {

            # Get a mapping entry
            my $entry = $mappings->{$to_field};

            if( $entry->{'action'} eq 'none' ) {

                # If the action is none, just stick the data in the new object
                $data->{$to_field} = $object->{$entry->{'from'}};

            }elsif( $entry->{'action'} eq 'call' || 
                    $entry->{'action'} eq 'recurse' ) {

                # We need to "do some magic"(tm)
                # TODO: Multiple call levels don't work
                my $obj = $object;
                foreach my $func (split /->/, $entry->{'from'}) {
                    if( $obj->can($func) ) {
                        $obj = $obj->$func;
                    }else {
                        $obj = $obj->{$func};
                    }
                }

                if( $entry->{'action'} eq 'recurse' ) {
                    if( $entry->{'type'} eq 'object-array' ) {
                        # We want to recurse into this each object in the arracy
                        $data->{$to_field} = [];
                        foreach my $single_obj (@$obj) {
                            push @{$data->{$to_field}},
                                 prep_object($single_obj);
                        }
                    }else{
                        # We want to recurse into this single object
                        $data->{$to_field} = prep_object($obj);
                    }
                }else{
                    # Just call the function and store the output
                    $data->{$to_field} = $obj;
                }
            }

            if( defined $data->{$to_field} ) {
                # Do any type translation we need
                if( $entry->{'type'} eq 'datetime' ) {
                    # HACK: Make this a string, which is iso8601 
                    # instead of a datetime type
                    # I'm too tired to figure out the correct way right now
                    $data->{$to_field} = Bugzilla::Util::datetime_from($data->{$to_field},'UTC') . '';
                }elsif( $entry->{'type'} eq 'string' ) {
                    $data->{$to_field} = $data->{$to_field} . '';
                }elsif( $entry->{'type'} eq 'boolean' ) {
                    if( $data->{$to_field} ) {
                         $data->{$to_field} = JSON::true;
                    }else {
                         $data->{$to_field} = JSON::false;
                    }
                }elsif( $entry->{'type'} eq 'int' ) {
                    $data->{$to_field} = $data->{$to_field} * 1;
                }elsif( $entry->{'type'} eq 'float' ) {
                    $data->{$to_field} = $data->{$to_field} * 1.0;
                }
            }
        }
    }

    # TODO: Support custom fields

    return $data;

}

# This takes an interface function and reverses the name lookups (without the
# other data)
# TODO: I'm sure there is a better perl way to do this with map
sub _reverse_interface {
    my $forward = shift;
    my $reverse = {};
    for my $a (keys %$forward) {
        my $b = $forward->{$a}->{'from'};
        $reverse->{$b} = $a;
        if( $forward->{$a}->{'names'} ) {
            foreach my $name ( @{$forward->{$a}->{'names'}} ) {
                $reverse->{$name} = $a;
            }
        }
    }
    return $reverse;
}


sub bug_reverse_interface {
    return _reverse_interface( bug_interface() );
}

sub bug_interface {
    my $mappings = {
        creation_time => {
            type   => 'datetime',
            from   => 'creation_ts',
            action => 'none',
        },
        last_change_time => {
            type   => 'datetime',
            from   => 'delta_ts',
            action => 'none',
        },
        id => {
            type   => 'int',
            from   => 'bug_id',
            action => 'none',
        },
        summary => {
            type   => 'string',
            from   => 'short_desc',
            action => 'none',
        },
        reporter => {
            type   => 'object',
            from   => 'reporter',
            action => 'recurse',
        },
        assigned_to => {
            type   => 'object',
            from   => 'assigned_to',
            action => 'recurse',
        },
        resolution => {
            type   => 'string',
            from   => 'resolution',
            action => 'none',
        },
        status => {
            type   => 'object',
            from   => 'status',
            names  => ['status_id','bug_status','status_obj'],
            action => 'recurse',
        },
        severity => {
            type   => 'string',
            from   => 'bug_severity',
            action => 'none',
        },
        priority => {
            type   => 'string',
            from   => 'priority',
            action => 'none',
        },
        product => {
            type   => 'object',
            from   => 'product_obj',
            names  => ['product_id'],
            action => 'recurse',
        },
        component => {
            type   => 'string',
            from   => 'component',
            action => 'none',
        },
        dupe_of => {
            type   => 'int',
            from   => 'dup_id',
            action => 'none',
        },
        keywords => {
            type   => 'object-array',
            from   => 'keyword_objects',
            names  => ['keyword_ids'],
            action => 'recurse',
        },
        flags => {
            type   => 'object-array',
            from   => 'flags',
            names  => ['flag_ids'],
            action => 'recurse',
        },
        platform => {
            type   => 'string',
            from   => 'rep_platform',
            names  => ['rep_platform'],
            action => 'none',
        },
        operating_system => {
            type   => 'string',
            from   => 'op_sys',
            names  => ['op_sys'],
            action => 'none',
        },
    };
}

sub user_reverse_interface {
    return _reverse_interface( user_interface() );
}
sub user_interface {
    my $mappings = {
        id => {
            type   => 'string',
            from   => 'userid',
            action => 'none',
        },
        real_name => {
            type   => 'string',
            from   => 'realname',
            action => 'none',
        },
        login => {
            type   => 'string',
            from   => 'login_name',
            action => 'none',
        },
    };
}

sub status_reverse_interface {
    return _reverse_interface( status_interface() );
}

sub status_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            action => 'none',
        },
        is_open => {
            type   => 'boolean',
            from   => 'is_open',
            action => 'none',
        },
        is_active => {
            type   => 'boolean',
            from   => 'is_active',
            action => 'none',
        },
        label => {
            type   => 'string',
            from   => 'value',
            action => 'none',
        },
    };
}

sub attachment_reverse_interface {
    return _reverse_interface( attachment_interface() );
}

sub attachment_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'attach_id',
            action => 'none',
        },
        creation_time => {
            type   => 'datetime',
            from   => 'creation_ts',
            names  => ['attached'],
            action => 'none',
        },
        last_changed => {
            type   => 'datetime',
            from   => 'modification_time',
            action => 'none',
        },
        bug => {
            type   => 'object',
            from   => 'bug',
            names  => ['bug_id'],
            action => 'recurse',
        },
        file_name => {
            type   => 'string',
            from   => 'filename',
            action => 'none',
        },
        summary => {
            type   => 'string',
            from   => 'description',
            action => 'none',
        },
        description => {
            type   => 'string',
            from   => 'description',
            action => 'none',
        },
        content_type => {
            type   => 'string',
            from   => 'mimetype',
            names  => ['contenttype'],
            action => 'none',
        },
        is_private => {
            type   => 'boolean',
            from   => 'isprivate',
            action => 'none',
        },
        is_obsolete => {
            type   => 'boolean',
            from   => 'isobsolete',
            action => 'none',
        },
        is_patch => {
            type   => 'boolean',
            from   => 'ispatch',
            action => 'none',
        },
    };
}

sub product_reverse_interface {
    return _reverse_interface( product_interface() );
}

sub product_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            action => 'none',
        },
        name => {
            type   => 'string',
            from   => 'name',
            action => 'none',
        },
    };
}

sub version_reverse_interface {
    return _reverse_interface( version_interface() );
}

sub version_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            names  => ['version_id'],
            action => 'none',
        },
        value => {
            type   => 'string',
            from   => 'value',
            action => 'none',
        },
        product => {
            type   => 'object',
            from   => 'product',
            names  => ['product_id'],
            action => 'recurse',
        },
    };
}

sub milestone_reverse_interface {
    return _reverse_interface( milestone_interface() );
}

sub milestone_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            names => ['milestone_id'],
            action => 'none',
        },
        product => {
            type   => 'object',
            from   => 'product',
            names  => ['product_id'],
            action => 'recurse',
        },
        value => {
            type   => 'string',
            from   => 'value',
            action => 'none',
        },
    };
}

sub keyword_reverse_interface {
    return _reverse_interface( keyword_interface() );
}

sub keyword_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            names => ['keyword_id'],
            action => 'none',
        },
        description => {
            type   => 'string',
            from   => 'description',
            action => 'none',
        },
        name => {
            type   => 'string',
            from   => 'name',
            action => 'none',
        },
    };
}

sub flag_reverse_interface {
    return _reverse_interface( flag_interface() );
}

sub flag_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            names => ['flag_id'],
            action => 'none',
        },
        status => {
            type   => 'string',
            from   => 'status',
            names  => ['value'],
            action => 'none',
        },
        type => {
            type   => 'object',
            from   => 'type',
            names  => ['flag_type','type_id','flagtype_id'],
            action => 'recurse',
        },
        set_by => {
            type   => 'object',
            from   => 'setter',
            names  => ['setter','setter_id'],
            action => 'recurse',
        },
        requestee => {
            type   => 'object',
            from   => 'requestee',
            names  => ['requestee_id'],
            action => 'recurse',
        },
        attachment => {
            type   => 'object',
            from   => 'attachment',
            action => 'recurse',
        },
        # Don't need to do bug here because we are folding the flag into
        # bug modification in Extension.pm
    };
}

sub flagtype_reverse_interface {
    return _reverse_interface( flagtype_interface() );
}

sub flagtype_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'id',
            names => ['flagtype_id','type_id'],
            action => 'none',
        },
        name => {
            type   => 'string',
            from   => 'name',
            action => 'none',
        },
    };
}

sub comment_reverse_interface {
    return _reverse_interface( comment_interface() );
}

sub comment_interface {
    my $mappings = {
        id => {
            type   => 'int',
            from   => 'comment_id',
            action => 'none',
        },
        bug => {
            type   => 'object',
            from   => 'bug',
            action => 'recurse',
        },
        attachment => {
            type   => 'object',
            from   => 'attachment',
            action => 'recurse',
        },
        author => {
            type   => 'object',
            from   => 'author',
            action => 'recurse',
        },
        when => {
            type   => 'datetime',
            from   => 'bug_when',
            action => 'none',
        },
        text => {
            type   => 'string',
            from   => 'thetext',
            action => 'none',
        },
        is_private => {
            type   => 'boolean',
            from   => 'isprivate',
            action => 'none',
        },
    };
}

1;
