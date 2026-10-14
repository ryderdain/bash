# checkssl.sh

The script `checkssl.sh` reads an SSL certificate and shows its most important data. It gets the certificate from a server or from a local certificate file. It then does a check of the certificate against the default root CAs. As an alternative, give a different CA file as the second argument.

## Usage

    ./checkssl.sh <fqdn | certfile> [<CAs file>]

## Requirements

- openssl
- ca_root_nss
- a Bourne shell
- an internet connection, if you give an FQDN

## Compatibility Notes

On Linux and on other BSD systems, the `date` command can use flags that are different from the FreeBSD flags. Use the flags that do `strptime()` on a string on your system. The `-v` flag operates on all these platforms, but a test on your system is necessary.
