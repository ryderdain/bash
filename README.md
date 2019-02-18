# CLI Toys / clitoys

To be read as "SEE-ELL-EYE-toys". Contains a personal collection of shell-based
tools and tricks for running from the command line, mostly written for BSD unix
systems. Attempts at cross-compatibility have been made where possible.

## checkssl.sh

Contacts, fetches, and pretty-prints the most useful information about an SSL key. 

### Usage
    ./checkssl.sh <fqdn>

### Requirements

- openssl
- ca_root_nss
- a bourne shell

### Compatibiity Notes

On Linux and other BSD's, `date` may require slightly different flags than on
FreeBSD. Use whatever flags you need to execute `strptime()` against a string.
The `-v` flag should work on all platforms as used here, but YMMV.

