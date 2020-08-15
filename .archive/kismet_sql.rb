#!/usr/bin/env ruby

# Very basic example for logging Kismet data to SQLite
# Would need to be expanded for more fields and better logging,
# contributions happily accepted

#   This file is part of Kismet
#
#   Kismet is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   Kismet is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with Kismet; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 'socket'
require 'date'
require 'time'
require 'kismet'
require 'pp'
require "getopt/long"
require "sqlite3"

include Getopt

def Mac2Int(mac)
	#puts "#{mac[0,2]} #{mac[3,2]} #{mac[6,2]} #{mac[9,2]} #{mac[12,2]} #{mac[15,2]}"
	i = 0

	i = i + (mac[0,2].to_i(16) << (5 * 8))
	i = i + (mac[3,2].to_i(16) << (4 * 8))
	i = i + (mac[6,2].to_i(16) << (3 * 8))
	i = i + (mac[9,2].to_i(16) << (2 * 8))
	i = i + (mac[12,2].to_i(16) << (1 * 8))
	i = i + mac[15,2].to_i(16)

	return i
end

def Int2Mac(macint)
	m = ""

	m = m + ((macint >> (5 * 8)) & 0xFF).to_s(16) 
	m = m + ((macint >> (4 * 8)) & 0xFF).to_s(16) 
	m = m + ((macint >> (3 * 8)) & 0xFF).to_s(16) 
	m = m + ((macint >> (2 * 8)) & 0xFF).to_s(16)
	m = m + ((macint >> (1 * 8)) & 0xFF).to_s(16) 
	m = m + ((macint) & 0xFF).to_s(16)

	return m
end

def ssidcb(proto, fields)
	# Only insert actual SSIDs into table
	if (fields['type'] == 2)
		return
	end

	$db.execute("BEGIN TRANSACTION")

	r = $db.execute("SELECT mac FROM ssid WHERE mac=?", [fields['mac']])

	if (r.length == 0)
		puts "INFO: new ssid #{fields["ssid"]}"

		$db.execute("INSERT INTO ssid (ssid, mac, type, wps_manuf, firsttime, lasttime) VALUES (?, ?, ?, ?, ?, ?)", [fields['ssid'], fields['mac'], fields['type'], fields['wps_manuf'], fields['firsttime'], fields['lasttime']])
	else
		puts "INFO: updating ssid #{fields["ssid"]}"
		
#		stm = $db.prepare "UPDATE ssid SET type=?, wps_manuf=?, lasttime=? WHERE ssid=? and mac=?"
		stm = $db.prepare "UPDATE ssid SET type=?, wps_manuf=?, lasttime=?, ssid=? WHERE rowid in (select max(rowid) from ssid where mac=?)"
		stm.bind_param 1, fields['type']
		stm.bind_param 2, fields['wps_manuf']
		stm.bind_param 3, fields['lasttime']
		stm.bind_param 4, fields['ssid']
		stm.bind_param 5, fields['mac']
		stm.execute
	end

	$db.execute("COMMIT")
end

def clientcb(proto, fields)

	puts "mac = #{fields["mac"]}, bssid = #{fields["bssid"]}, type = #{fields["type"]}"

	# Ensure we're only dealing with clients and not access points
#	if (fields['type'] == '0' 
	    #or fields['bssid'] == fields['mac']
#	    )
#		puts "#{fields["mac"]} is an access point"
#		puts "select type, count(*) from ssid where mac = '#{fields["mac"]}';"

#		return
#	end

	$db.execute("BEGIN TRANSACTION")

	r = $db.execute("SELECT mac from ssid where mac like ?", "#{fields['mac'][0..14]}%")

	$db.execute("COMMIT")

	if (r.length != 0)
		puts "#{fields["mac"]} is an access point"

		# Uncomment this to clean up client table
		# 
		# Delete it from client
		$db.execute("BEGIN TRANSACTION")
		$db.execute("DELETE FROM client where mac = ?", [fields['mac']])
		$db.execute("COMMIT")
		return
	end


	if (fields['bssid'] == fields['mac'])
		fields['bssid'] = ''
	end
	$db.execute("BEGIN TRANSACTION")

	stm = $db.prepare "SELECT lasttime from client WHERE mac=? order by lasttime desc limit 2"
	stm.bind_param 1, fields['mac']
	r = stm.execute

	if (row = r.next) 
		# Check if we've seen this device in the last 15 minutes
		if (row[0].to_i > (fields['lasttime'].to_i - 900))
			update = 1
		else
			update = 0
		end
	else
		# Never seen this device before
		update = 0
	end

	if (update == 1)
		# Update record if it's less than 15 minutes old
		puts "INFO: updating mac #{fields["mac"]}"

		# Get previous time we last saw this device and insert it if it exists 
		if (row = r.next)
			stm = $db.prepare "UPDATE client SET bssid=?, type=?, manuf=?, signal_dbm=?, lasttime=?, previoustime=? WHERE rowid in (select max(rowid) from client where mac=?)"
			stm.bind_param 6, row[0]
			stm.bind_param 7, fields['mac']
		else
			stm = $db.prepare "UPDATE client SET bssid=?, type=?, manuf=?, signal_dbm=?, lasttime=? WHERE rowid in (select max(rowid) from client where mac=?)"

			stm.bind_param 6, fields['mac']
		end
		stm.bind_param 1, fields['bssid']
		stm.bind_param 2, fields['type']
		stm.bind_param 3, fields['manuf']
		stm.bind_param 4, fields['signal_dbm']
		stm.bind_param 5, fields['lasttime']

		stm.execute

	else
		# Create a new record if one does not exist or it's greater than 15 minutes old
		puts "INFO: new record for mac #{fields["mac"]}"
	#	$db.execute("BEGIN TRANSACTION")

		$db.execute("INSERT INTO client (mac, bssid, type, manuf, signal_dbm, firsttime, lasttime) VALUES (?, ?, ?, ?, ?, ?, ?)", [fields['mac'], fields['bssid'], fields['type'], fields['manuf'], fields['signal_dbm'], fields['lasttime'], fields['lasttime']])
	#	$db.execute("COMMIT")
	end
	$db.execute("COMMIT")
end

host = "localhost"
port = 2501
sqlfile = "kismet.sql3"

opt = Long.getopts(
	["--host", "", REQUIRED],
	["--port", "", REQUIRED],
	["--database", "", REQUIRED]
	)

if opt["host"]
	host = opt["host"]
end

if opt["port"]
	if opt["port"].match(/[^0-9]+/) != nil
		puts "ERROR:  Invalid port, expected number"
		exit
	end

	port = opt["port"].to_i
end

if opt["database"]
	sqlfile = opt["database"]
end

puts "INFO: Logging to database file #{sqlfile}"

if not File::exists?(sqlfile)
	puts "Creating database"
	$db = SQLite3::Database.new(sqlfile)
	$db.execute("BEGIN TRANSACTION")
	$db.execute("CREATE TABLE ssid (ssid TEXT, mac TEXT, type INTEGER, wps_manuf TEXT, firsttime DATETIME, lasttime DATETIME)")
	$db.execute("CREATE TABLE client (mac TEXT, bssid TEXT, type INTEGER, manuf TEXT, signal_dbm INTEGER, firsttime DATETIME, lasttime DATETIME, previoustime DATETIME)")
	$db.execute("CREATE TABLE notes (mac TEXT, note TEXT)")
	$db.execute("COMMIT")
else
	$db = SQLite3::Database.new(sqlfile)
end

$db.busy_timeout(20000)

puts "INFO: Connecting to Kismet server on #{host}:#{port}"
$k = Kismet.new(host, port)

$k.connect()

$k.run()

$k.subscribe("ssid", ["ssid", "mac", "type", "wps_manuf", "firsttime", "lasttime"], Proc.new {|*args| ssidcb(*args)})

$k.subscribe("client", ["mac", "bssid", "type", "manuf", "signal_dbm", "firsttime", "lasttime"], Proc.new {|*args| clientcb(*args)})

$k.wait()
