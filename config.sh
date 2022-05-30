#!/bin/bash

echo "*****************************************************************"
echo "Note: docker & openvswitch-switch must be installed on your host"
echo "*****************************************************************"

addVnic()
{
#expose network namespace
NETNS=`docker inspect -f '{{.State.Pid}}' $1`

if [ ! -d /var/run/netns ]; then
    mkdir /var/run/netns
fi
if [ -f /var/run/netns/$NETNS ]; then
    rm -rf /var/run/netns/$NETNS
fi

ln -s /proc/$NETNS/ns/net /var/run/netns/$NETNS

#add virtual interface to container and connect to virtual brdige
CONTAINER=$1
OVS_BR=$2
PORT=$3
NETNS=`docker inspect -f '{{.State.Pid}}' $CONTAINER`

OVS_BRs=($(ovs-vsctl list-br | awk '{ print $1 }'))
if [[ " ${OVS_BRs[*]} " =~ " ${OVS_BR} " ]]; then
    echo ""
else
   ovs-vsctl add-br $OVS_BR
fi

ovs-vsctl add-port $OVS_BR $PORT -- set Interface $PORT type=internal
ip link set $PORT netns $NETNS
ip netns exec $NETNS ip link set dev $PORT up

echo "VIRTUAL INTERFACE SUCCESSFULLY ADDED!"
}

firewall()
{
echo "Enter container name:"
read contname
echo "Enter network name:"
read netname


netnames=($(docker network ls | awk '{ print $2 }'))
if [[ " ${netnames[*]} " =~ " ${netname} " ]]; then
    echo "Network exist"
else
   echo "*Network does not exist, a new one will be created*"
   echo "Enter network address: (including '/subnet')"
   read subnet
   echo "Enter network gateway:"
   read GW
   docker network create --subnet=$subnet --gateway=$GW $netname >/dev/null
   echo "NETWORK $netname CREATED!"
fi

echo "Enter container ip address:"
read ipadd

echo "Enter volume name:"
read volname

volnames=($(docker volume ls | awk '{ print $2 }'))
if [[ " ${volnames[*]} " =~ " ${volname} " ]]; then
    echo ""
else
   echo "*Volume does not exist, a new one will be created*"
   docker volume create $volname >/dev/null
   echo "VOLUME $volname CREATED!"
fi

docker run -dit --privileged -v $volname:/var/log --network=$netname --ip=$ipadd --name $contname abukareem/docker-firewall >/dev/null
echo "============================="
echo "CONTAINER $contname CREATED!"
echo "============================="
echo "(Adding a virtual interface to the container)"
echo "Enter virtaul bridge name and virtual interface name: (in-line)"
read vbr vnic
addVnic $contname $vbr $vnic

echo "Enter ip address for $vnic interface (including '/subnet'):"
read vip
docker exec -it $contname ip addr add $vip dev $vnic
}

service()
{
echo "Enter image name:"
read imgname
echo "Enter service name:"
read srvname

docker run -dit --cap-add=NET_ADMIN --name $srvname $imgname >/dev/null
echo "============================="
echo "CONTAINER $srvname CREATED!"
echo "============================="
echo "(Adding a virtual interface to the container)"
echo "Enter virtaul bridge name and virtual interface name: (in-line)"
read vbr vnic
addVnic $srvname $vbr $vnic

echo "(PLEASE WAIT...)"
docker exec -it $srvname apt update >/dev/null
docker exec -it $srvname apt install iputils-ping iproute2 isc-dhcp-client -y >/dev/null
docker network disconnect bridge $srvname
echo "DONE!"
}

while : ; do
echo ""
echo "1. Configure Firewall Container"
echo "2. Add Service"
echo "3. Add Virtual Interface"
echo "4. Exit"
echo -n "Enter choice: "
read choice 

case $choice in
	1) firewall 
	;;
	2) service
	;;
	3) echo "Enter container, virtaul bridge, and vNIC names: (in-line)" 
	   read cont vbr vnic
	   addVnic $cont $vbr $vnic 
	;;
	*) exit
	;;
esac
done
