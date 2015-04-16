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
moment = require('moment')


class Calendar
  constructor: (@url) ->
    @calendarData = {}

  loadEvents: (cb) ->
    @calendarData = {}
    ical.fromURL @url, {}, (err, data) =>
      return cb(err) if err?

      for _, evnt of data
        if evnt.type == 'VEVENT'
          eventDate = moment(new Date(evnt.start)).format('YYMMDD')
          @calendarData[eventDate] ?= []
          @calendarData[eventDate].push(evnt)

      return cb()


  getEventsToday: () ->
    return @calendarData[moment().format('YYMMDD')] || []



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
      startTime = moment(new Date(evnt.start)).utcOffset(14).format('h:mma')
      endTime = moment(new Date(evnt.end)).utcOffset(14).format('h:mma')
      return "#{startTime}-#{endTime} today: #{evnt.summary} (#{evnt.location})"
    .forEach (evnt) ->
      robot.messageRoom room, evnt

  refreshCron = new CronJob refreshFrequency, refresh, null, true, 'America/Los_Angeles'
  alertCron = new CronJob alertFrequency, messageTodaysEvents, null, true, 'America/Los_Angeles'
  refresh()

