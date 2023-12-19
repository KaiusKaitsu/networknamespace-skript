#!/bin/bash

#Script to automatically create a network namespace with openvpn running inside
#Version 3.11.23 By Kaius Koivisto

 start() {

  
   #Get the real ip to compare against it later
   real_ip=$(curl -s ipinfo.io | grep -o '"ip": "[^"]*' | grep -o '[^"]*$')
   echo $real_ip 

   #free resolv.conf incase it's being used
   resolvconf -u

   #Create networknamespace (netns)
   ip netns add myvpn 

   #create loop back device to the netns 
   ip netns exec myvpn ip addr add 127.0.0.1/8 dev lo
   ip netns exec myvpn ip link set lo up

   #create virtual ethernet between netns and the main interface

   ip link add vpndest0 type veth peer name vpnsource0 
   timer=0
   while ! ip a | grep -q vpndest0; do sleep 0.1; done
   echo "Pair created"

   ip link set vpndest0 up
   timer=0
   while  ! ip a | grep -q vpndest0.*MULTICAST,UP; do sleep 0.1; done
   echo "vpndest0 is up"
  
   ip link set vpnsource0 netns myvpn up
   timer=0
   while  ! ip a | grep -q vpndest0.*LOWER_UP; do sleep 0.1; done 
   echo "vpnsource0 linked to myvpn netns"

   #Assign ip addresses to the created virtual ethernet
   ip addr add 10.200.200.1/24 dev vpndest0
   echo "ip 10.200.200.1 assigned to vpndest0"
   ip netns exec myvpn ip addr add 10.200.200.2/24 dev vpnsource0
   echo "ip 10.200.200.2 assigned to vpnsource0"
   ip netns exec myvpn ip route add default via 10.200.200.1 dev vpnsource0
   echo "10.2000.200.1 and 10.200.200.2 linked"

   #Rules and services that will run inside the netns
   iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o enp+ -j MASQUERADE
   iptables -A FORWARD -o enp+ -i vpndest0 -j ACCEPT
   iptables -A FORWARD -i enp+ -o vpndest0 -j ACCEPT
   echo "iptables changed"  

   socat tcp-listen:9091,reuseaddr,fork tcp-connect:10.200.200.2:9091 & 
   PID_socat=$!
   echo "socat port link created from namespace 9091 to mainspace"

   #Start vpn inside the namespace
   ip netns exec myvpn openvpn  --config /etc/openvpn/mullvad.conf &
   PID_openvpn=$!
   echo "openvpn service started inside netns myvpn"
   
   current_ip=$(ip netns exec myvpn curl -s ipinfo.io | grep -o '"ip": "[^"]*' | grep -o '[^"]*$')
   
   #Wait until the vpn ip is active 
   while [[ "$current_ip" == "$real_ip" ]] ; do
   current_ip=$(ip netns exec myvpn curl -s ipinfo.io | grep -o '"ip": "[^"]*' | grep -o '[^"]*$')

   sleep 5; done
   echo "IP changed from $real_ip to $current_ip"
   
   #Start transmission when it's safe
   if [ "$current_ip" != "$real_ip" ]; then
     systemctl start transmission-daemon
     echo "transmission service started"
   fi

}

 stop() {
   #Transmission can be stopped with systemd
   systemctl stop transmission-daemon

   # Kill the non-systemD processes 'gracefully (-15)'  with Linux process ID
   if [ "$PID_socat" ]; then
     kill -15 "$PID_socat"
   else
     killall -15 socat
   fi
   echo "shutdown socat"

   if [ "$PID_openvpn" ]; then
     kill -15 "$PID_openvpn"
   else
     killall -15 openvpn
   fi
   echo "shutdown openvpn"

   # Undo all the networking
   iptables -t nat -D POSTROUTING -s 10.200.200.0/24 -o enp+ -j MASQUERADE
   echo "iptable route closed"
   ip link set vpndest0 down
   echo "IP link vpndest0 down"
   ip link delete vpndest0
   echo "vpndest0 deleted"
   ip netns delete myvpn
   echo "networknamespace myvpn deleted"
   
   #Often openvpn instance doesnt release resolv.conf file after shutdown, force it
   resolvconf -u

}

"$@"
  




