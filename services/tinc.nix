{ config, lib, pkgs, ... }:

{
  services.tinc.networks."darknet" = {
    hosts = {
      tsar_su = ''
Address = tsar.su
Subnet 10.0.0.1
-----BEGIN RSA PUBLIC KEY-----
MIICCgKCAgEA3MJhddZEerldvwE+etG72cJYeRzJLgz0QvEogC+rLwDRsfSD7N2R
VcTtpwrQI9W+N+xlFjUDQS9t4F0PpVGWFpsxC4zjH3nMAf1KgQ0RKeUzLaykiTfD
KBrUfe5VgjKGfM7X/wgHD+Kt4kup+fm1K3L1SxX9iHFq15+4ypyNUIZSt2RDZDeu
T9jwU6cOruRVz0/eI2ke6qwcZO7j1qVHdYUl3kcM8ncCYbOyrqXvUAnKC+k+CNKm
jiJwDFb9hoaeZJl5NDb3R0jCPh3UTbkiFs3LPJIbngHbFDXC1Z2zyj8ucERie6eC
2FhCXfN0Lq76nAVOT0wCZNAEIuHAFKemAnYFoKVxozKtjeJ2H45v2sVHwNknnWbr
O8uOVjkDwsrvZmLpy5k7M2iGahn3Q2TsIKPETS5Us6jqHyBsUizDX2FTro48ZQrD
NoDbKxhNbQ6MyAK2/zb1Xrj7dQWKWnDBBlrsHQN0atyqa4iCgOxmXcEcF3rOp3HP
MkBaMchUKanqib4HW3lmt5Tkp1qJB0fQumDCz7LeAyswHW6stdrLsExhRKFKDu79
0OimIqUrtgqp/8hQnB63BA10nJh0Jye4RH3kiq85kVvyv2sQA8OOkQX+k5mefoG2
ZM3vOuYrHhB+zWk2Vm9BEL9GKHWwyRl8MrAeGvTBaGuILB+Uar2gxh8CAwEAAQ==
-----END RSA PUBLIC KEY-----
      '';
      nixhost = ''
Subnet 10.0.0.2
-----BEGIN RSA PUBLIC KEY-----
MIICCgKCAgEAmz0K9uy0NnQK+DNrPq6iKsdZcT70i9K12nRvcm1x4hEVvEnPMW2X
RRztH9NEZHjlt2aOzheq5YUasoJEDIDuhNSgvb9vvSwznw/mP6uKd67v2TMKC0tC
RkC3BK4RPOAr7X9nACo9+0WU6Q/qvtds8SFx2v+OsQF6tkv5E5iSGlbrQMzIstFK
tWDZ8gbxoXE9NdQyGjgcCpE4GSy/BWUPfzoFpWqPG/5hucCZ3nz22QREK6+BRj6w
7UQkHxG5wxSLkiftUPG+hXejJwVtokhkISmOFAmrRttzIMyNLVfMzg1HzlYZBzlx
OY4glQxGV8T7Ti8jQEnytTM85IvKRWMb4X9JcLOBsl/Az5sGi+x+9Dmze004i3/2
iSD1/YX3gj1cIom+fOaP/KqRMJQK4C15Go2poWdxwjy1nFywr/a1wTUe4zty1RMH
8dNUNXQkfcP7Bq8vESC26l7l6JYAIqYlOUxncJEIDFe1qiRXmPI98fd6vrntpyOZ
ZqeaYEKM8Y//v17FjAMZYALvYt7eDEWb84v8nNRd5/YTJmjolzsI3ZMU6SXgwvHJ
36jsQo7G+NmpFpLWZBWJ+/MZbAcksnaJ4h3470hHUhQBj4KOvcsJQtmMwjq8Fg2P
AddZiU/4B+zsXy/s4sMKHuR/jQUje8ljzsHCylDRfali2Ngjf0A+BA0CAwEAAQ==
-----END RSA PUBLIC KEY-----
      '';
      Georges-Mac-Pro = ''
Subnet 10.0.0.3
-----BEGIN RSA PUBLIC KEY-----
MIICCgKCAgEAuU6j1lJrCZ5Ryrg8pE9ZUKmrk10zZ7yJuim88W6vpW2U7t1lt6wk
8+PQhKnWt7Bico/QfOqQDfNmj+BCDniwRIZjiSyS47i1oO48zAvWHfrX019QX8Ho
TGz1+2co9rlbt1wVK6qr+XCCPT3oPHkukLgs2CdAZJt4H3yaJt3jPAY5lnuKMf91
U4ckLAQ423r3ravZvdVLYbp6yJNXYgn+XpOU2QwwI3E9tmtzKdiJOmjON8vI7Fdo
O3V9Zea6odiL2Mr1uBoHPu9N2mQ+ScnsUarl76ByDiLA5r4bZfZN9SK8vaB7Vr9u
YNLy3Rsrky861DAg3Fcz0waPWW9Q5z+GjDpoP3h6PonQM6GSuOg2YueFqxsPKQfb
r4+nyApD5meHxmdeMRU6g8RZskSQLW/KNvUKWTtSJGXRGMvY/5rXnjyAymVFqp0J
uCWGGJGYJpny+1E1tSx16MQRrUlKr/WmeVzozGmHphIUT0mcqKrHGMSdbmnDN2p/
6VO/s3OdQ+7f5WSrbsdiwy/QKTM3fEdodrw6uftYy1IJed7aREafpuGeCpzzKcen
p8K0r7dC07oNmXTNz3hGQfPJZS75ITksnzBdlIIyT82LTEMA3cJvJ8iYqdk8MHx0
VawXLt19cpKxZhhmuNQnIOKms0/H208UKaQg1LJGwaLslS7S3IEKscsCAwEAAQ==
-----END RSA PUBLIC KEY-----
'';
    };
    extraConfig = ''
      ConnectTo tsar_su
    '';
  };
  networking.firewall.allowedUDPPorts = [ 655 ];
}
