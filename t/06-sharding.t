use Test;

use Cache::Async;

my $cache = Cache::Async.new(num-shards => 10, producer => sub ($k) { return "B$k"; });

plan 60;

for ^20 -> $i {
    $cache.put("X$i", "A$i");
    ok((await $cache.get("X$i")) eq "A$i", "previously put' content returned");


    ok((await $cache.get("Y$i")) eq "BY$i", "generated content returned");
    ok((await $cache.get("Y$i")) eq "BY$i", "generated content returned again");
}

# XXX test in parallel

done-testing;
