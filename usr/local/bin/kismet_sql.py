#!/usr/bin/env python

"""
A complete basic utility using the python REST API and the KismetRest python
library.

Uses Kismet to monitor:
    - A list of devices identified by MAC address (via --mac option)
    - A list of devices identified by beaconed SSID (via --ssid option)
    - A list of devices identified by probed SSID (via --probed option)
"""

import sys
import KismetRest
import argparse
import time
import sqlite3
import os

# Per-device function called for each line in the ekjson.  Notice that we use the
# field simplification system to reduce the number of devices we're looking at.

# We use a global to keep track of the last timestamp devices were seen, so that
# we can over-sample the timeframe in kismet but only print out devices which have
# updated
last_ts_cache = {}
def per_device(d):
    key = d['kismet.device.base.key']

    # Only process clients - not interested in base stations
#    if d['kismet.device.base.type'] != 'Wi-Fi Client' and d['kismet.device.base.type'] != 'Wi-Fi Device' and d['kismet.device.base.type'] != 'BTLE':
#    if d['kismet.device.base.type'] == 'Wi-Fi AP':
#        return
   
    # Check the cache and don't process devices which haven't updated
    if key in last_ts_cache:
        if last_ts_cache[key] == d['kismet.device.base.last_time']:
            return

    last_ts_cache[key] = d['kismet.device.base.last_time']
    
    # Gather SSID
    ssid = ""

#    if 'dot11.device.last_beaconed_ssid' in d and not d['dot11.device.last_beaconed_ssid'] == "":
#       ssid = d['dot11.device.last_beaconed_ssid']
#    elif 'dot11.device.last_probed_ssid' in d and not d['dot11.device.last_probed_ssid'] == "":
#        ssid = d['dot11.device.last_probed_ssid']
    ssid = d['dot11.device.last_bssid']
    if ssid != '': 
        cur.execute("select commonname, max(lasttime) from client where mac='{ssid}' group by mac" \
            .format(
                ssid=ssid))
        row = cur.fetchone()
        if not row is None:
            if not row[0] == '':
                ssid=row[0]

    if d['kismet.device.base.commonname'] != d['kismet.device.base.macaddr']:
        commonname = d['kismet.device.base.commonname']
    else:
        commonname = ""

    # Fix output of manuf - grab eveything after "\011" if it exists
    d['kismet.device.base.manuf'] = d['kismet.device.base.manuf'].replace("\\484949","*")
    if "*" in d['kismet.device.base.manuf']:
        d['kismet.device.base.manuf'] = d['kismet.device.base.manuf'].split("*")[1]

    previoustime = ''
    # Check if a recent record exists
    cur.execute("SELECT lasttime from client WHERE mac='{mac}' order by lasttime desc limit 2".format(mac=d['kismet.device.base.macaddr']))

    row = cur.fetchone()
    if not row is None:
        # There is a recent record. Check if it's less than 15mins old
        if row[0] > d['kismet.device.base.last_time'] - 900:
            # The record is less than 15mins old. Let's update it
            update = 1
        else:
            # The record is older than 15mins. Let's create a new record
            update = 0
            # Let's set the previoustime to lasttime of the last record in case there's only one record
            previoustime = row[0]
    else:
        # No record exists for the device. Let's create a new record
        update = 0


    # Check if there's a second last record, and get the previoustime accordingly
    row = cur.fetchone()
    if not row is None:
        previoustime = row[0]

    if update == 1:
        db.execute("UPDATE client SET server_uuid='{server_uuid}', commonname='{commonname}', ssid='{ssid}', manuf='{manuf}', signal='{signal}', lasttime='{lasttime}', previoustime='{previoustime}', devtype='{devtype}', lat='{lat}', lon='{lon}' \
                WHERE rowid in (select max(rowid) from client WHERE mac='{mac}')"\
                .format(
                    server_uuid=d['kismet.device.base.server_uuid'],
                    commonname=commonname,
                    ssid=ssid, 
                    manuf=d['kismet.device.base.manuf'], 
                    signal=d['kismet.common.signal.last_signal'], 
                    lasttime=d['kismet.device.base.last_time'], 
                    previoustime=previoustime, 
                    devtype=d['kismet.device.base.type'],
                    mac=d['kismet.device.base.macaddr'],
                    lat=d['kismet.common.location.avg_lat']/float(1000000),
                    lon=d['kismet.common.location.avg_lon']/float(1000000)))
    else:
        db.execute("INSERT INTO client (server_uuid, mac, commonname, ssid, manuf, signal, firsttime, lasttime, previoustime, devtype, lat, lon) \
                VALUES ('{server_uuid}', '{mac}', '{commonname}', '{ssid}', '{manuf}', '{signal}', '{firsttime}', '{lasttime}', '{previoustime}', '{devtype}', '{lat}', '{lon}')"\
                .format(
                    server_uuid=d['kismet.device.base.server_uuid'],
                    mac=d['kismet.device.base.macaddr'], 
                    commonname=commonname,
                    ssid=ssid, 
                    manuf=d['kismet.device.base.manuf'], 
                    signal=d['kismet.common.signal.last_signal'], 
                    firsttime=d['kismet.device.base.last_time'], 
                    lasttime=d['kismet.device.base.last_time'],
                    previoustime=previoustime,
                    devtype=d['kismet.device.base.type'],
                    lat=d['kismet.common.location.avg_lat']/float(1000000),
                    lon=d['kismet.common.location.avg_lon']/float(1000000)))
    db.commit()

    print "{}, {}, {}, {}, {}, {}, {}, {}, {}".format(
            d['kismet.device.base.server_uuid'],
            d['kismet.device.base.commonname'],
            d['kismet.device.base.manuf'],
            ssid,
#            time.ctime(d['kismet.device.base.first_time']),
            time.ctime(d['kismet.device.base.last_time']),
            d['kismet.common.signal.last_signal'],
            d['kismet.device.base.type'],
            d['kismet.common.location.avg_lat']/float(1000000),
            d['kismet.common.location.avg_lon']/float(1000000))
uri = "http://kismet:GrDzRFcqc4m08pQb@localhost:2501"

rate = 5

sqlfile = "/var/local/kismet.sql3"

parser = argparse.ArgumentParser(description='Kismet SQL')

parser.add_argument('--uri', action="store", dest="uri")
parser.add_argument('--rate', action="store", dest="rate")
parser.add_argument('--database', action="store", dest="sqlfile")

results = parser.parse_args()

if results.uri != None:
    uri = results.uri

if results.rate != None:
    rate = results.rate

if results.sqlfile != None:
    sqlfile = results.sqlfile

print "Using database {}".format(sqlfile)
if not os.path.exists(sqlfile):
    db = sqlite3.connect(sqlfile, 20000)
    db.execute("CREATE TABLE client (server_uuid TEXT, mac TEXT, commonname TEXT, ssid TEXT, devtype TEXT, manuf TEXT, signal INTEGER, firsttime DATETIME, lasttime DATETIME, previoustime DATETIME, lat DOUBLE, lon DOUBLE)")
    db.commit()
else:
    db = sqlite3.connect(sqlfile, 20000)

# Create cursor
cur = db.cursor()

kr = KismetRest.KismetConnector(uri)
kr.set_debug(1)

regex = []

regex = None
results.macs = None

# Simplify the fields to what we want to print out

fields = [
    'kismet.device.base.key',
    'kismet.device.base.server_uuid',
    'kismet.device.base.commonname',
    'kismet.device.base.macaddr',
    'kismet.device.base.type',
    'kismet.device.base.manuf',
    'kismet.device.base.last_time',
    'kismet.device.base.signal/kismet.common.signal.last_signal',
    'dot11.device/dot11.device.last_beaconed_ssid',
    'dot11.device/dot11.device.last_probed_ssid',
    'dot11.device/dot11.device.last_bssid',
    'kismet.device.base.location/kismet.common.location.avg_lat',
    'kismet.device.base.location/kismet.common.location.avg_lon',
]

while True:
    # Scan for mac addresses individually
    if results.macs != None:
        for m in results.macs:
            # device_by_mac returns a vector, turn that into calls of our 
            # device handling function
            for d in kr.device_by_mac(m, fields):
                per_device(d)
    else:
        # Otherwise, look for devices which have changed, and which optionally match 
        # any of our regexes, within our time range * 2

        # Generate a negative timestamp which is our rate, 
        ts = (rate * 2) * -1

        kr.smart_device_list(callback = per_device, regex = regex, fields = fields, ts = -900)

    time.sleep(rate)


