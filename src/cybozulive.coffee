{CronJob} = require 'cron'
{OAuth} = require 'oauth'
{parseString} = require 'xml2js'
moment = require 'moment'
Promise = require 'bluebird'

entrypoint_url = 'https://api.cybozulive.com/api'
request_token_url = 'https://api.cybozulive.com/oauth/initiate'
authorize_url = 'https://api.cybozulive.com/oauth/authorize?oauth_token='
access_token_url = 'https://api.cybozulive.com/oauth/token'
consumer_key = process.env.HUBOT_CYBOZULIVE_NOTIFIER_CONSUMER_KEY
consumer_secret = process.env.HUBOT_CYBOZULIVE_NOTIFIER_CONSUMER_SECRET
groupId = process.env.HUBOT_CYBOZULIVE_NOTIFIER_GROUP_ID
channel = 'general'

cybozulive = new OAuth(
  request_token_url,
  access_token_url,
  consumer_key,
  consumer_secret,
  '1.0',
  null,
  'HMAC-SHA1'
)

module.exports = (robot) ->
  cronjob = new CronJob(
    cronTime: "0 */10 * * * *"
    start: true
    timeZone: "Asia/Tokyo"
    onTick: ->
      checkUpdate()
  )

  request = (path) ->
    new Promise (resolve, reject) ->
      cybozulive.get(
        entrypoint_url + path,
        robot.brain.get('accessToken'),
        robot.brain.get('accessTokenSecret'),
        (e, data, res) ->
          if e
            reject(e)
            return
          parseString data, (err, result) ->
            if err
              reject(err)
              return
            resolve(result.feed)
      )

  getNotifications = ->
    new Promise (resolve, reject) ->
      request('/notification/V2?group='+groupId).then (res) ->
        resolve(res.entry)

  checkUpdate = () ->
    console.log(robot.brain.get('latestUpdate'))
    getNotifications().then (notifications) ->
      for n in notifications.reverse()
        title = n.title[0]
        [author, authorId] = n.author[0].name
        updatedAt = moment(n.updated[0])
        group = n['cbl:group'][0]['$'].valueString
        link = n.link[0]['$']['href']
        category = n.category.map((c) -> c['$']['term'])[1]
        summary = if n.summary then n.summary[0]['_'] else ''

        if updatedAt > robot.brain.get('latestUpdate')
          robot.brain.set 'latestUpdate', updatedAt

          robot.emit 'slack.attachment',
            channel: channel
            username: 'cybozulive'
            icon_url: 'http://labs.cybozu.co.jp/images/wp_cybozulive_icon.png'
            content:
              fallback: summary
              color: "gray"
              author_name: author
              author_icon: "https://api.cybozulive.com/api/icon/V2?type=user&user="+authorId
              title: title
              title_link: link
              text: summary
              fields: [{
                title: "Edited At"
                value: updatedAt.tz('Asia/Tokyo').format("YYYY-MM-DD HH:mm:ss")
                short: true
              }]
        else
          continue

        console.log(JSON.stringify(n, null, 2))

  robot.hear /^cybozulive authorize$/, (res) ->
    cybozulive.getOAuthRequestToken((err, token, secret, results) ->
      if err
        res.send 'Error occured'
      else
        console.log token, secret, results
        robot.brain.set 'oauthToken', token
        robot.brain.set 'oauthSecret', secret
        res.send authorize_url+token
    )

  robot.hear /^cybozulive verify (.*)/, (res) ->
    verifier = res.match[1]
    cybozulive.getOAuthAccessToken(
      robot.brain.get('oauthToken'),
      robot.brain.get('oauthSecret'),
      verifier,
      (err, access_token, access_token_secret, results) ->
        if err
          res.send 'Error occured'
        else
          robot.brain.set 'accessToken', access_token
          robot.brain.set 'accessTokenSecret', access_token_secret
          res.send 'Verified'
    )
