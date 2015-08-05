# Description:
#   Provide Daily Notifications about events today
#
# Notes:
#
#   Sample command line usage:
#   `HUBOT_CALENDAR_ALERTS_LOCATION_FILTER='San Francisco' HUBOT_CALENDAR_ALERTS_URL='http://espn.go.com/travel/sports/calendar/export/espnCal?teams=5_26' HUBOT_CALENDAR_ALERTS_ROOM=announcements ./bin/hubot`
#

CronJob = require('cron').CronJob
ical = require('ical')
# moment = require('moment')
moment = require('moment-timezone')
request = require('request')
icalendar = require('icalendar')


# via http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
escapeRegExp = (str)->
  return str.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&")



badTimezone = '''
BEGIN:VTIMEZONE
TZID:America/New_York
X-LIC-LOCATION:America/New_York
BEGIN:DAYLIGHT
TZOFFSETFROM:-0400
TZOFFSETTO:-0300
TZNAME:EDT
DTSTART:19700308T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:-0300
TZOFFSETTO:-0400
TZNAME:EST
DTSTART:19701101T020000
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
END:STANDARD
END:VTIMEZONE
'''

badRe = new RegExp(escapeRegExp(badTimezone.replace(/(?!\r)\n/gi, '\r\n')), "gi");


goodTimezone = '''
BEGIN:VTIMEZONE
TZID:America/New_York
X-LIC-LOCATION:America/New_York
BEGIN:DAYLIGHT
TZOFFSETFROM:-0500
TZOFFSETTO:-0400
TZNAME:EDT
DTSTART:19700308T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:-0400
TZOFFSETTO:-0500
TZNAME:EST
DTSTART:19701101T020000
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
END:STANDARD
END:VTIMEZONE
'''

cal = 'VERSION:2.0\nCALSCALE:GREGORIAN\nMETHOD:PUBLISH\nX-WR-CALNAME:ESPN CALENDAR\nX-WR-TIMEZONE:America/New_York\nBEGIN:VTIMEZONE\nTZID:America/New_York\nX-LIC-LOCATION:America/New_York\nBEGIN:DAYLIGHT\nTZOFFSETFROM:-0400\nTZOFFSETTO:-0300\nTZNAME:EDT\nDTSTART:19700308T020000\nRRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU\nEND:DAYLIGHT\nBEGIN:STANDARD\nTZOFFSETFROM:-0300\nTZOFFSETTO:-0400\nTZNAME:EST\nDTSTART:19701101T020000\nRRULE:FREQ=YEARLY;BYMONTH=1'

class Calendar
  constructor: (@url) ->
    @calendarData = {}

  loadEvents: (cb) ->
    @calendarData = {}

    request @url, (err, response, body) =>
      if err? or response?.statusCode isnt 200
        console.log "ERRORz", err?.message, response?.statusCode

      else
        # console.log(body)
        console.log body.substring(0, 500)
        console.log "==========="
        body = body.replace(badRe, goodTimezone)
        console.log body.substring(0, 500)
        try

          data = icalendar.parse_calendar(body) #, tz)
          events = data.events()
          for evnt in events
            # console.log evnt.getPropertyValue('DTSTART')
            # console.log evnt.getProperty('DTSTART')
            eventDate = moment(new Date(evnt.getPropertyValue('DTSTART'))).tz('America/Los_Angeles').format('YYMMDD')
            @calendarData[eventDate] ?= []
            @calendarData[eventDate].push({
              start: evnt.getPropertyValue('DTSTART')
              end: evnt.getPropertyValue('DTEND')
              summary: evnt.getPropertyValue('SUMMARY') || ''
              location: evnt.getPropertyValue('LOCATION') || ''
            })

            # eventDate = moment(new Date(evnt.properties.DTSTART)).format('YYMMDD')
             # { DTSTART: [Object],
             #   DTEND: [Object],
             #   DTSTAMP: [Object],
             #   SUMMARY: [Object],
             #   UID: [Object],
             #   LOCATION: [Object],
             #   TRANSP: [Object] } } ]
          console.log "Registered #{Object.keys(@calendarData).length} dates"
        catch e
          console.log "Error parsing"
          console.trace e
      return cb()


  getEventsToday: () ->
    return @calendarData[moment().tz('America/Los_Angeles').format('YYMMDD')] || []



module.exports = (robot) ->

  # Default to every weekday at 8:00am
  alertFrequency = process.env.HUBOT_CALENDAR_ALERTS_FREQUENCY || '00 00 8 * * 1-5'
  # Default to every weekday at 7:55am
  refreshFrequency = process.env.HUBOT_CALENDAR_REFRESH_FREQUENCY || '00 55 7 * * 1-5'

  calendarUrl = process.env.HUBOT_CALENDAR_ALERTS_URL
  room = process.env.HUBOT_CALENDAR_ALERTS_ROOM
  location = new RegExp(process.env.HUBOT_CALENDAR_ALERTS_LOCATION_FILTER || ".*", 'i')

  unless calendarUrl? and room?
    missingVars = []
    missingVars.push("HUBOT_CALENDAR_ALERTS_URL") unless calendarUrl?
    missingVars.push("HUBOT_CALENDAR_ALERTS_ROOM") unless room?
    robot.logger.warning("Calendar Alerts disabled: missing environment variables #{missingVars.join(', ')}")
    return null

  calendar = new Calendar(calendarUrl)

  refresh = () ->
    calendar.loadEvents (err) ->
      return console.log(err) if err?

  messageTodaysEvents = () ->
    events = calendar.getEventsToday().filter (evnt) ->
      return location.test(evnt.location)
    .map (evnt) ->
      # ical cannot parse Google calendar exports with timezone... hack UTC offset
      # see https://github.com/peterbraden/ical.js/issues/50
      console.log(JSON.stringify(evnt));
      startTime = moment(new Date(evnt.start)).tz('America/Los_Angeles').format('h:mma')
      endTime = moment(new Date(evnt.end)).tz('America/Los_Angeles').format('h:mma')
      return "#{startTime}-#{endTime} today: #{evnt.summary} (#{evnt.location})"
    .forEach (evnt) ->
      robot.messageRoom room, evnt

  refreshCron = new CronJob refreshFrequency, refresh, null, true, 'America/Los_Angeles'
  alertCron = new CronJob alertFrequency, messageTodaysEvents, null, true, 'America/Los_Angeles'
  refresh()

