module golang.zx2c4.com/wireguard/apple

go 1.25.6

require (
	golang.org/x/sys v0.41.0
	golang.zx2c4.com/wireguard v0.0.0-20230209153558-1e2c3e5a3c14
)

require (
	github.com/davecgh/go-spew v1.1.2-0.20180830191138-d8f796af33cc // indirect
	github.com/oschwald/maxminddb-golang/v2 v2.1.1 // indirect
	github.com/pmezard/go-difflib v1.0.1-0.20181226105442-5d4384ee4fb2 // indirect
)

require (
	github.com/google/btree v1.1.3 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	// github.com/maxminddb-golang v0.0.0 // indirect
	github.com/miekg/dns v1.1.72 // indirect
	golang.org/x/crypto v0.46.0 // indirect
	golang.org/x/mod v0.31.0 // indirect
	golang.org/x/net v0.48.0 // indirect
	golang.org/x/sync v0.19.0 // indirect
	golang.org/x/time v0.12.0 // indirect
	golang.org/x/tools v0.40.0 // indirect
	golang.zx2c4.com/wintun v0.0.0-20230126152724-0fa3db229ce2 // indirect
	gvisor.dev/gvisor v0.0.0-20260129214308-cb856800aa1c // indirect
)

replace (
	github.com/oschwald/maxminddb-golang/v2 => ./maxminddb-golang
	golang.zx2c4.com/wireguard => ./netnavi
	gvisor.dev/gvisor => gvisor.dev/gvisor v0.0.0-20250205023644-9414b50a5633
	tailscale.com => ./tailscale
)
