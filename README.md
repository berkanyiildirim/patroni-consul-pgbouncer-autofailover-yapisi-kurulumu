# PostgreSQL Patroni + Consul + PgBouncer + Consul-template ile Autofailover Yapısının Kurulumu

[Patroni](https://patroni.readthedocs.io/en/latest/#), PostgreSQL HA Cluster yapısının kurulması ve yönetimi için kullanılan open source bir araçtır. Patroni, PostgreSQL Cluster’ının bootstrap işlemlerini gerçekleştirmesi, replikasyon kurulumu ve en önemlisi otomatik failover sağlaması kabiliyetine sahiptir. Patroni otomatik failover yapısını sağlamak için bir Distributed Configuration Store (DCS) aracına ihtiyaç duyar. Bunlardan bazıları; ETCD, Consul, ZooKeeper, Kubernetes.

[Consul](https://www.consul.io); service discovery, distributed key-value store, health checking özellikleriyle kendini tanımlayan high available bir DevOps ürünü olarak ifade edilebilir. Node’lar üzerinde konumlanan, server veya client moddaki agentlar ile çalışan Consul, node’un ve kendine tanımlanmış servislerin sağlık durumlarını gözlemler, dağıtık olarak anahtar-değer ikililerini muhafaza ve servis eder, dinamik servislerin mevcut konumlarını (en temel haliyle IP:PORT olarak ifade edilebilir) bilir ve talep karşılığında iletir. Ayrıca, consul-template aracı ile de dinamik konfigürasyon yönetimleri sağlar.

## Test Ortamı için Kurulan Yapı
![Test Ortamı için Kurulan Yapı](https://github.com/berkanyiildirim/patroni-consul-pgbouncer-autofailover-yapisi-kurulumu/blob/master/images/patroni-consul.png)

Çalışma kapsamında genel kullanım olan Patroni+ETCD ikilisi yerine DCS aracı olarak Consul tercih edilmiştir. Büyük sistemlerde kullanımı gerekli olan pgBouncer connection pooler aracının patroni lider değişiminde konfigürasyon ayarlarını güncellemek için consul-template kullanılmış ve patroni + [pgbouncer](https://www.pgbouncer.org) + consul + [consul-template](https://github.com/hashicorp/consul-template) yapısı test edilmiştir. 

Yapı içerisinde Patroni-PostgreSQL ve Consul kurulu 3'lü clusterlar mevcuttur. Patroni clusterı içerisinde pgBouncer kullanımı gerektirmeyen veya uygulama seviyesinde connection pooler kurulumu (HikariCp vb.) sağlayan küçük sistemler için herbir makinanın asıl ip'si yanında bir de gezen ip tanımlanmıştır. Sadece leader makina tarafından set edilip leader değişiminde silinecek bu ip, consul-template tarafından yönetilmektedir.

---

## Test Ortamı Kurulumu

Test ortamının kurulumu için [vagrant](https://www.vagrantup.com) kullanılmıştır. Kurulumda kullanılan Vagrantfile dosyası /vagrant altında verilmiştir.

## Consul Cluster Kurulumu

Verilen Vagrantfile ile test ortamının kurulumu tamamlandıktan sonra consul cluster kurulumuna yapılır. consul-node{1..3} makinalarına verilen `install_consul.sh` scripti ile consul kurulumu yapılır. Key-value değerlerini depolayacak olan consul `setup_consul_server.sh` scripti ile server modda konfigüre edilir. "setup_consul_server.sh" script dosyası çalıştırılmadan önce `NODENAME` ve `NODEIP` değişkenleri herbir node için özel olarak ayarlanmalıdır.

Test dışı kurulumlarda consul konfigürasyon dosyası */etc/consul.d/config.json*'daki `encrypt` key alanı ilk consul kurulduktan sonra `consul keygen` komutunun çıktısı ile değiştirilmelidir. Her node aynı "encrypt" key değerini kullanmalıdır.    

Verilen scriptler ile herbir node'da kurulum ve ayarlamalar tamamlandıktan sonra `consul validate /etc/consul.d/config.json` komutu ile consul konfigürasyon dosyaları kontrol edilir. "Configuration is valid!" mesajı alındığında consul servisleri sırayla başlatılır:

```sh
sudo systemctl start consul
sudo systemctl enable consul
```

Kurulum sonunda consul clusterımız şu şekilde olur:
```
[root@consul-node1 vagrant]# consul members
Node       Address            Status  Type    Build  Protocol  DC   Segment
consul-01  192.168.60.2:8301  alive   server  1.9.2  2         dc1  <all>
consul-02  192.168.60.3:8301  alive   server  1.9.2  2         dc1  <all>
consul-03  192.168.60.4:8301  alive   server  1.9.2  2         dc1  <all>
```

Ayrıca Consul IU arayüzüne kurulan node'ların herhangi birinin IP'si ile erişilir. örn. http://192.168.60.4:8500/ui/

## Consul Agent'ların Client Modda Kurulumu

Patroni ve pgBouncer kurulan node'larda consul cluster ile iletişimi "Consul Client" yapar. Böylece Patroni ve pgBouncer daima local agentlar ile konuşur ve consul clusterında oluşabilecek failover işlemlerinden etkilenmez. Single-point-of-failure önlenir.

Herbir Patroni ve pgBoucner makinalarına `install_consul-client.sh` ile consul kurulum yapılır, consul'ü client modda ayarlamak için `setup_consul-client.sh` script dosyası çalıştırılır. Bu dosya çalıştırılmadan önce `node_name` ve `bind_addr` alanları kurulum yapılan herbir node için spesifik olarak ayarlanmalıdır. Herbir consul client için "encrypt" key değeri consul cluster kurulumdaki key değeri ile aynı olmalıdır.

Test dışı ve farklı IP'li kurulumlarda, kurulan consul cluster IP'lerini belirten `retry_join` alanını değiştirdiğinizden emin olun.

Sağlan script dosyaları ile kurulum ve ayarlamalar yapıldıktan sonra consul-client servisi nodelarda sırayla başlatılır:
```sh
sudo systemctl daemon-reload
sudo systemctl start consul-client
sudo systemctl enable consul-client
```

Consul clusterımız son hali şekilde olur:
```
[root@pg-patroni1 vagrant]# consul members
Node              Address             Status  Type    Build  Protocol  DC   Segment
consul-01         192.168.60.2:8301   alive   server  1.9.2  2         dc1  <all>
consul-02         192.168.60.3:8301   alive   server  1.9.2  2         dc1  <all>
consul-03         192.168.60.4:8301   alive   server  1.9.2  2         dc1  <all>
patroni1-client   192.168.60.11:8301  alive   client  1.9.2  2         dc1  <default>
patroni2-client   192.168.60.12:8301  alive   client  1.9.2  2         dc1  <default>
patroni3-client   192.168.60.13:8301  alive   client  1.9.2  2         dc1  <default>
pgbouncer-client  192.168.60.14:8301  alive   client  1.9.2  2         dc1  <default>
```

## Patroni Cluster Kurulumu

Buraya kadar consul cluster'ı oluşturan 3 makinada consul server, patroni clusterını oluşturan 3 makinada ve pgBouncer makinasında ise consul client kurulumunu tamamladı. Bu aşamada Patroni kurulumu yapılır. 

Patroni kurulumu yapılmadan önce replikasyon için patroni makinaları arasında root kullanıcısı için passwordless ssh sağlanmalıdır. 

```sh
ssh-keygen -t rsa -b 4096 -C "your_email@domain.com"
ssh-copy-id root@server_ip_address
```

`install_pg.sh` ve `install_patroni.sh` script dosyaları ile herbir patroni makinasında PostgreSQL ve Patroni kurulumu yapılır. `setup_patroni.sh` ile de patroni konfigürasyonları yapılır. Bu script dosyasını kullanırken `NODEIP` ve `NAME` değişkenlerinin kurulum yapılan makinaya özel olarak ayarladığınızdan emin olun.

Herbir makinada kurulum yapıldıktan sonra sırayla Patroni servisleri başlatılır. Patroni clusterı başlatılmadan önce consul clusterının sağlıklo çalıştığından emin olun.
```sh
sudo systemctl daemon-reload
sudo systemctl start patroni.service
sudo systemctl enable patroni.service
```

Servisler başlatıldıktan sonra Patroni cluster durumu:
```
[root@pg-patroni1 vagrant]# sudo patronictl -c /opt/app/patroni/etc/postgresql.yml list
+ Cluster: postgres (6928171320490488783) -------+----+-----------+
|    Member   |      Host     |  Role  |  State  | TL | Lag in MB |
+-------------+---------------+--------+---------+----+-----------+
| pg-patroni1 | 192.168.60.11 | Leader | running |  4 |           |
| pg-patroni2 | 192.168.60.12 |        | running |  4 |         0 |
| pg-patroni3 | 192.168.60.13 |        | running |  4 |         0 |
+-------------+---------------+--------+---------+----+-----------+
```

Buraya kadar yapılan kurulumlarla Patroni + Consul yapısını sağlamış olduk. Aşağıda verilen yönetim komutlarını kullanılarak failover testleri yapılabilir. Amaçlanan yapıya ulaşmak için geriye değişen lider IP'lerini PgBouncer *pgbouncer.ini* dosyasına dinamik işleyecek ve node'lar üzerinde gezen ip ayarlamasını yapacak consul-template kurulum ve ayarlamaları kaldı. 

Bazı patroni yönetim komutları:
```sh
#check cluster state
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml list

# stop patroni
sudo systemctl stop patroni

# check failover history
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml history

# manually initiate failover
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml failover

# disable auto failover
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml pause
```

## PgBouncer ve Consul-template Kurulumu

Consul-template aracı consul binary paketiyle birlikte gelmez. Ayrı ayrı kurulmaları gerekir. Bu yüzden önce pgBouncer makinasına consul client kurulumu yapılır. PgBouncer, consul cluster ile bu local agent üzerinden konuşur. PgBouncer + Consul + Consul-template çalışma yapısı şu şekildedir: 
![PgBouncer + Consul + Consul-template Yapısı](/images/pgbouncer-consul.png)

PgBouncer ve consul-template kurulum scriptleri `install_pgbouncer.sh` ve `install_consul-template.sh` dosyalarında verilmiştir.

PgBouncer authentication için aşağıdaki komut herhangi bir patroni makinasında çalıştırılarak çıktısı [`userlist.txt`](/scripts/userlist.txt) dosyasına eklenir. 
````sql
select rolname,rolpassword from pg_authid where rolname='postgres';
````

örnek: 
```text
"postgres" "md53175bce1d3201d16594cebf9d7eb3f9d"
```

pgBouncer servisi başlatılır.
```sh
service pgbouncer start
service pgbouncer enable
```

PgBouncer kurulumu yapıldıktan sonra */etc/pgbouncer/pgbouncer.ini* dosyasını render edecek consul-template şablonu oluşturulur. Bu şablon consul clusterdaki patroni verilerini tutan `postgres` servisini izler, lider değişiminde *pgbouncer.ini* dosyasında IP ve port değerlerini dinamik olarak değiştirir. **Kurulan bu yapıyla yapılan testlerde Patroni failover sırasında uygulamadan gelen istekler 15-20 saniyelik aksaklıktan sonra sorunsuz devam etmiştir.**

*/etc/pgbouncer/* altında `pgbouncer.ini.tmpl` isimli bir template dosyası yaratılıp [burada](/templates/pgbouncer.ini.tmpl) verilen içerik kopyalanır. Bu local consul agent ile konuşan consul-template'in pgBouncer konfigürasyon dosyasını değiştirken kullanacağı şablondur. Consul-template, parametreleri [*consul-template-config.hcl*](/templates/consul-template-config.hcl) dosyasında verilerek çalıştırılır. 

consul-template'i çalıştırmak için: 
```sh
/opt/consul-template -config=consul-template-config.hcl
```

## Floating IP'nin Yapıya Eklenmesi

Buraya kadar yapılan kurulum ve ayarlamalar ile Patroni-pgBouncer-Consul yapısı sağlanmıştır. Yukarda belirttiğimiz gibi bgBouncer ihtiyacı olmayan ve/veya uygulama sevisinde HikariCP gibi connection poolerlar kullanan küçük sistemler için, sadece liderler tarafından kullanılan bir gezen ip (192.168.50.55) tanımlanmıştır. Lider makinalarda bu gezen ip'nin set edilmesi için yine consul-template aracından faydalanılmıştır. Consul-template verilen şablon ile Consul cluster'dan local agent aracılığıyla T anındaki lideri sorgular. Lider makina bu sorgulama ile gezen ip'nin kensinde set edilmesi gerektiğini öğrenir ve consul-template çalıştırma dosyasında (floating-ip.htcl) verilen script ile ip'yi kendi üzerinde set eder. Aynı şekilde lider değişiminde gezen ip önceki liderden silinip yeni lider tarafından set edilir.

Verilen script dosyalarında gezen ip değeri consul üzerinde bir key-value olarak */service/postgres/floating-ip* 'de tutulmaktadır. Consul üzerine key-value değeri eklemek için consul UI veya [`consul kv put`](https://www.consul.io/commands/kv/put) komutunu kullanabilirsiniz.

Floating IP'nin yapıya eklenmesi için ilk olarak Patroni clusterı içindeki makinalarda consul-template kurulumu yapılır. Kurulum script [dosyası](install_consul-template.sh). 

Kurulum ve gezen ip değerinin consule eklenmesi yapıldıktan sonra /opt altında `floating-ip.tmpl` şablon dosyası oluşurulup içeriği consulden o an ki lideri sorgulacak şekilde ayarlanır. [floating-ip.tmpl]() şablonundaki "{{if eq $leader "pg-patroni1"}}" bloğunu kurulum yapacağınız herbir makina için değiştirdiğinizden emin olun. Daha sonra her lider değişiminde consul-template'in çalıştıracağı [`floating-ip.sh`]() script dosyası oluşturulur. Bu script ile sadece liderin gezen ip'ye sahip olması sağlanır. Son olarak consul-template'in çalışma parametrelerini verdiğimiz `floating-ip.htcl` dosyası oluşturulup herbir makinada çalıştırılır.

consul-template'i çalıştırmak için: 
```sh
/opt/consul-template -config=floating-ip.htcl
```

Consul-template'in çalışmasıyla herbir makinanın home dizininde oluşturulan `floating-ip.txt` dosyasına bakarak gezen ip'ye sahip olup olmadığını görebilirsiniz. Gezen ip'yi gözlemlemek için `ip a | grep 'inet '` komutu da faydalı olabilir.

