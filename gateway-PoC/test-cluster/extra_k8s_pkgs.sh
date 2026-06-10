#!/usr/bin/env bash
# (의도적으로 비움)
#
# MetalLB는 더 이상 CP 프로비저닝 중에 적용하지 않는다. tainted CP 단독 노드에서는
# MetalLB controller가 스케줄 불가(Pending)라, 여기서 동기 적용하면 controller
# Ready 대기가 timeout 되고 IPAddressPool 적용이 실패해 프로비저닝 전체가 중단된다
# (워커 생성 전 중단됨). 그래서 MetalLB 적용을 up.sh 로 옮겨 모든 노드가 Ready 된
# 뒤(=워커에 controller 스케줄 가능) 실행한다. metallb.sh 참조.

exit 0
