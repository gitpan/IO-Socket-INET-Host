
=head1 NAME

IO::Socket::INET::Host - very simple straightforward  TCP server

=head1 SYNOPSIS

	use IO::Socket::INET::Host;

	my $host = new IO::Socket::INET::Host(
		port => 5000,
		timeout => 20,
		callback => {
			add => \&add,
			remove => \&remove,
			data => \&data,
		},
	);

	$host->run;

	sub add {
		my $io = shift;

		$io->print("Welcome, ", $io->peerhost, ".\n";

		return !0;
	}

	sub remove {
		my $io = shift;

		warn $io->peerhost, " left.\n";
	}

	sub data {
		my $io = shift;

		my $line = $io->getline;
		
		$line =~ s/\r?\n//;

		if($line eq 'quit') {
			$io->print("Bye.\n");
			return 0;
		}
		else {
			$io->print("You wrote: $line\n");
			return !0;
		}
	}

=head1 DESCRIPTION

This modules aims to provide a simple TCP server. It will listen on a port you
specify, accept incoming connections and remove them again when they're dead.
It provides three simple callbacks at the moment, but I plan to add a few more.

=head1 METHODS

=over 4

=item B<new>(...)

This is the constructor. It takes all the information the server needs as
parameter. Currently, the following options are supported.

=over 4

=item B<port>

The port to listen on.

=item B<host>

The host to bind to (hostname or IP).

=item B<timeout>

The time to wait for actions in seconds. This is simply passed to
L<IO::Select>.

=item B<callback>

A reference to a hash with function references assigned to callback names.
Currently, three callbacks are supported. "add" is called when a new connection
was accepted. If it returns a false value, the connection is kicked again right
away. "remove" is called when a connection got lost. "data" is called when
there's pending data on a connection. If the callback function returns false,
the connection is removed afterwards. All callbacks are called with the peer
socket as argument (L<IO::Socket::INET>).

=back

=item B<callback>(add => \&add, remove => \&remove, data => \&data)

This method overwrites callbacks set up with the constructor.

=item B<run>(no parameters at all)

Enter the main loop. Won't ever return.

=back

=head1 BUGS

This module was hacked together within a few minutes, so there are probably
lots of bugs. On the other hand, it's very few code, so there can't be that
much bugs in it. Just try it out and tell me if it's broken.

=head1 TODO

=over 4

=item * Add tests to the package.

=item * Add a "tick" callback that is called after every cycle (for maintenance
tasks).

=item * ...

=back

=head1 COPYRIGHT

Copyright (C) 2008 by Jonas Kramer <jkramer@cpan.org>. Published under the
terms of the Artistic License 2.0.

=cut

package IO::Socket::INET::Host;

use strict;
use warnings;

use Carp;

use IO::Socket::INET;
use IO::Select;


sub new {
	my ($class, %rc) = @_;

	croak "Called with no/invalid port.\n" if(!$rc{port} or $rc{port} =~ /\D/);

	return bless {
		port => $rc{port},
		host => $rc{host} || 'localhost',
		callback => $rc{callback} || {},
		timeout => $rc{timeout},
	}, $class;
}


# add, remove, data, idle
sub callback {
	my ($self, $callback) = @_;

	@{$self->{callback}}{keys %$callback} = values %$callback;
}


sub run {
	my ($self) = @_;

	my $host = new IO::Socket::INET(
		LocalHost => $self->{host},
		LocalPort => $self->{port},
		Proto => 'tcp',
		ReuseAddr => !0,
		Listen => 32,
	) or return;

	$self->{select} = new IO::Select($host);

	while(!0) {
		my $select = $self->{select};

		for my $io ($select->can_read) {
			if($io == $host) {
				my $peer = $io->accept;
				my $code = $self->{callback}->{add};

				if($code) {
					if(&{$code}($peer)) {
						$select->add($peer);
					}
					else {
						$peer->shutdown(SHUT_RDWR);
					}
				}
			}
			else {
				my $code = $self->{callback}->{data};
				if($code) {
					if(!&{$code}($io)) {
						my $code = $self->{callback}->{remove};

						&{$code}($io) if($code);

						$select->remove($io);
						$io->shutdown(SHUT_RDWR);
						$io->close;
					}
				}
			}
		}

		for my $peer ($select->handles) {
			if($peer != $host and !$peer->connected) {
				my $code = $self->{callback}->{remove};

				&{$code}($peer) if($code);

				$peer->shutdown(SHUT_RDWR);
				$peer->close;
				
				$select->remove($peer);
			}
		}
	}
}


!0;
