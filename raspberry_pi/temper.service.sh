#!/sbin/openrc-run

description="Temperature monitor with ntfy alerts"

command="/usr/local/bin/temper"
command_user="agarpi:agarpi"
supervisor="supervise-daemon"
respawn_delay=5
output_log="/var/log/temper.log"
error_log="/var/log/temper.log"

depend() {
	need net
	use dns
}

start_pre() {
	checkpath --file --owner "$command_user" --mode 0640 "$output_log"
}
