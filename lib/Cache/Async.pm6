unit class Cache::Async;

use String::CRC32;

has &.producer;
has Int $.num-shards = 1;
has Int $.max-size = 1024;
has Duration $.max-age;

my class Shard {

    has &.producer;
    has $.max-size;
    has Duration $.max-age;

    my class Entry {
        has Str $.key;
        has $.value is rw;
        has $.timestamp is rw; # XXX would like this to be Instant but then it can't be nullable
        has Entry $.older is rw;
        has Entry $.younger is rw;
        has Promise $.promise is rw;
    }

    has Entry %!entries = {};
    has Entry $!youngest;
    has Entry $!oldest;
    has Lock $!lock = Lock.new;
    has atomicint $!hits = 0;
    has atomicint $!misses = 0;

    method !unlink($entry) {
        if ! defined $entry {
            die "unlinking undefined entry!";
        }
        if defined $!youngest && $!youngest === $entry {
            $!youngest = $entry.older;
        }
        if defined $!oldest && $!oldest === $entry {
            $!oldest = $entry.younger;
        }
        if defined $entry.older {
            $entry.older.younger = $entry.younger;
            $entry.older = Nil;
        }
        if defined $entry.younger {
            $entry.younger.older = $entry.older;
            $entry.younger = Nil;
        }
    }

    method !link($entry) {
        if defined $!youngest {
            $!youngest.younger = $entry;
        }
        $entry.older = $!youngest;
        $!youngest = $entry;
        if ! defined $!oldest {
            $!oldest = $entry;
        }
    }

    method !expire-by-count() {
        while (%!entries.elems > $!max-size) {
            my $evicted = $!oldest;
            my $key = $evicted.key;
            %!entries{$evicted.key}:delete;
            self!unlink($evicted);
        }
    }

    method !expire-by-age($now) {
        while (defined $!oldest) && ($!oldest.timestamp < ($now - $!max-age)) {
            # XXX duplication from above
            my $evicted = $!oldest;
            my $key = $evicted.key;
            %!entries{$evicted.key}:delete;
            self!unlink($evicted);
        }
    }

    method get($key --> Promise) {
        my $entry;
        my $now = Nil;
        $!lock.protect({
            if defined $!max-age {
                $now = now;
                self!expire-by-age($now);
            }
            $entry = %!entries{$key};
            if ! defined $entry {
                atomic-inc-fetch($!misses);
                $entry = Entry.new(key => $key, timestamp => $now);
                %!entries{$key} = $entry;
                self!link($entry);            
                $entry.promise = Promise.start({
                    $!lock.protect({
                        $entry.value = &.producer.($key);
                        $entry.promise = Nil;
                    });
                    $entry.value;
                });
                self!expire-by-count();
                return $entry.promise;
            }
            else {
                if defined $entry.promise {
                    atomic-inc-fetch($!misses);
                    return $entry.promise;
                }
                else {
                    atomic-inc-fetch($!hits);
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
            my $removed = %!entries{$key};
            if defined $removed {
                self!unlink($removed);
            }
            %!entries{$key}:delete;
        });
    }

    method clear() {
        $!lock.protect({
            %!entries = %();
            $!youngest = Nil;
            $!oldest = Nil;
        });
    }

    method hits-misses() {
        my $current-hits = atomic-fetch($!hits);
        my $current-misses = atomic-fetch($!misses);
        atomic-fetch-sub($!hits, $current-hits);
        atomic-fetch-sub($!misses, $current-misses);
        return ($current-hits, $current-misses);
    }
}

has Shard @shards;

submethod TWEAK() {
    @shards = Shard.new(max-size => $!max-size, max-age => $!max-age, producer => &!producer) xx $!num-shards;
}

method !shard-id($key) {
    if ($!num-shards == 1) {
        return 0;
    }
    else {
        return String::CRC32::crc32($key) % $!num-shards;
    }
}

method get($key --> Promise) {
    # XXX return seems to (sometimes) await the future? investigate and
    # understand...
    @shards[self!shard-id($key)].get($key);
}

method put($key, $value) {
    return @shards[self!shard-id($key)].put($key, $value);
}

method remove($key) {
    return @shards[self!shard-id($key)].remove($key);
}

method clear() {
    for @!shards {
        .clear;
    }
}

method hits-misses() {
    my $total-current-hits = 0;
    my $total-current-misses = 0;
    for @!shards {
        my ($shard-hits, $shard-misses) = @shards[0].hits-misses;
        $total-current-hits += $shard-hits;
        $total-current-misses += $shard-misses;
    }
    return ($total-current-hits, $total-current-misses);
}

