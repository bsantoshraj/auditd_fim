#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

TEST_USER="auditd_test_user"
TEST_GROUP="auditd_test_group"

run_test "Group add" "fim.identity" "groupadd $TEST_GROUP"
run_test "User add" "fim.identity" "useradd -g $TEST_GROUP $TEST_USER"
# Use 'sudo' group on Debian/Ubuntu, 'wheel' on RHEL/CentOS
ADMIN_GROUP="sudo"
getent group sudo &>/dev/null || ADMIN_GROUP="wheel"
run_test "User mod" "fim.identity" "usermod -aG $ADMIN_GROUP $TEST_USER"
run_test "Password change" "fim.identity" "echo '$TEST_USER:Test123!' | chpasswd"
run_test "User delete" "fim.identity" "userdel $TEST_USER"
run_test "Group delete" "fim.identity" "groupdel $TEST_GROUP"
