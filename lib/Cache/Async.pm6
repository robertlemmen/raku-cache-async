unit class Cache::Async;

my class Entry {
    has Str $.key;
    has $.value is rw;
    has Instant $.timestamp is rw;
    has Entry $.prev is rw;
    has Entry $.next is rw;
    has Promise $.promise is rw;
}

has &.producer;
has Int $.max-size = 1024;
has Duration $.max-age;

has Entry %!entries = {};
has Entry $!youngest;
has Entry $!oldest;
has Lock $!lock = Lock.new;

# XXX nicer constructor

# XXX linked list, timestamps, limit size and so on

# XXX tests

# XXX measure throughput

# XXX we could use some sort of overhand locking scheme to make the lock on the
# entries struct taken for shorter amoutns of time, needs measurement though.
# sharding could solve that problem as well

# XXX sharding

method get($key) {
    my $entry;
    $!lock.protect({
        $entry = %!entries{$key};
        if ! defined $entry {
            $entry = Entry.new(key => $key);
            $entry.promise = Promise.start({
                $!lock.protect({
                    $entry.value = &.producer.($key);
                    $entry.promise = Nil;
                });
                $entry.value;
            });
            # XXX expire old entries
            return $entry.promise;
        }
        else {
            if defined $entry.promise {
                return $entry.promise;
            }
            else {
                my $ret = Promise.new;
                $ret.keep($entry.value);
                return $ret;
            }
        }
    });
}

method put($key, $value) {
    $!lock.protect({
        my $entry = %!entries{$key};
        if ! defined $entry {
            $entry = Entry.new(key => $key, value => $value);
            %!entries{$key} = $entry;
        }
        $entry.value = $value;
        # XXX expire old entries
    });
}

method remove($key) {
    $!lock.protect({
        %!entries{$key}:delete;
    });
}

method clear() {
    $!lock.protect({
        %!entries = {};
        $!youngest = Nil;
        $!oldest = Nil;
    });
}
