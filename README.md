# Forge

Personal collection of shell-based tools and tricks for running from the command line, mostly written for BSD unix systems. Attempts at cross-compatibility have been made where possible.

## checkssl.sh

Contacts, fetches, and pretty-prints the most useful information about an SSL key. Attempts to verify the certificate against default root CAs, but can be passed an alternative CAs file to use instead.

### Usage
    ./checkssl.sh <fqdn | certfile> [<CAs file>]

### Requirements

- openssl
- ca_root_nss
- a bourne shell
- internet, if fetching with fqdn

### Compatibiity Notes

On Linux and other BSD's, `date` may require slightly different flags than on
FreeBSD. Use whatever flags you need to execute `strptime()` against a string.
The `-v` flag should work on all platforms as used here, but YMMV.

