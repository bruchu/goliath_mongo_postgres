Goliath Mongo Postgres Example
------------------------------

This is a simple toy example that accesses both mongo and postgres
through a [Goliath async webserver](https://github.com/postrank-labs/goliath).

Much of the code was lifted and rearranged from these demos:

  - [http_log.rb](https://github.com/postrank-labs/goliath/blob/master/examples/http_log.rb)
  - [auth\_and\_rate_limit.rb](https://github.com/postrank-labs/goliath/blob/master/examples/auth_and_rate_limit.rb)

Reasons:

  - I was having some difficulties getting postgres + mongo to work
     (likely due to user error) at the same time in the Goliath
     framework.
  - I did not want to proxy to endpoint unless the rate limit was
    checked before hand
    - this appeared to be a short-coming of the previous
      Goliath::Rack::AsyncAroundware auth_and_rate_limit.rb
      implementation, which now looks to have been replaced by
      Goliath::Rack::BarrierAroundwareFactory.

# Setup

## Setup Database

This sets up gmp_development with a simple 'partners' table, with a key of "a"

`
% cd bin
`
`
% bash setup_db.sh
`
`
% bundle install
`

## Run server

`
% bundle exec ruby mongo_pg.rb -sv
`

### forwarding example

`
% curl -v 'http://localhost:9000/horoscope?app=a'
`

### missing key example

`
% curl -v 'http://localhost:9000/horoscope?app=b'
`
