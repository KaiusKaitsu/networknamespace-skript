# networknamespace-script
Little script project for my personal use
This script creates a networkname space with openvpn &amp; transmission daemons. It makes sure that the IP has changed before starting transmission. You should run this script as a systemd service


Systemd service file
# /etc/systemd/system/myvpn.service
 [Unit]
 Description=Networknamespace running openvpn

 [Service]
 User=root
 Type=oneshot
 ExecStart=/home/[USER]/skripti.sh start
 ExecStop=/home/[USER]/skripti.sh stop
 RemainAfterExit=true

 [Install]
 WantedBy=multi-user.target
