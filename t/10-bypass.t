use Test;

use Cache::Async;

plan 13;

my $producer-count;

# normal behavior: do cache undefined return values
$producer-count = 0; 
my $cache = Cache::Async.new(producer => sub ($k) { $producer-count++; if $k ~~ /no/ { return Nil; } else { return 42; } });

ok((defined await $cache.get('key1')), 'Value returned for regular case');
ok((! defined await $cache.get('nokey')), 'Nil returned for special case');
is($producer-count, 2, 'Producer called expected number of times');
ok((! defined await $cache.get('nokey')), 'Nil returned for special case');
is($producer-count, 2, 'Producer called expected number of times');

# cache set up to not cache undefined values
$producer-count = 0; 
$cache = Cache::Async.new(producer => sub ($k) { $producer-count++; if $k ~~ /no/ { return Nil; } else { return 42; } },
                             cache-undefined => False);
ok((defined await $cache.get('key1')), 'Value returned for regular case');
ok((! defined await $cache.get('nokey')), 'Nil returned for special case');
ok((! defined await $cache.get('nokey')), 'Nil returned for special case');
is($producer-count, 3, 'Producer called expected number of times');

# still not caching undefined values, but producer returns a promise
$producer-count = 0; 
$cache = Cache::Async.new(producer => sub ($k) { $producer-count++; if $k ~~ /no/ { return Promise.kept(Nil); } else { return Promise.kept(42); } },
                             cache-undefined => False);
ok((defined await $cache.get('key1')), 'Value returned for regular case');
ok((! defined await $cache.get('nokey')), 'Nil returned for special case');
ok((! defined await $cache.get('nokey')), 'Nil returned for special case');
is($producer-count, 3, 'Producer called expected number of times');

done-testing;
