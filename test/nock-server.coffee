#
#    Copyright 2016 Jon Freedman
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

EventEmitter = require 'events'
Log = require('log')
logger = new Log process.env.HUBOT_LOG_LEVEL or process.env.HUBOT_SYMPHONY_LOG_LEVEL or 'info'

nock = require 'nock'
uuid = require 'node-uuid'

class NockServer extends EventEmitter

  constructor: (@host, startWithHelloWorldMessage = true) ->
    logger.info "Setting up mocks for #{@host}"

    @streamId = 'WLwnGbzxIdU8ZmPUjAs_bn___qulefJUdA'

    @firstMessageTimestamp = 1461808889185

    @realUserId = 7215545078229

    @botUserId = 7696581411197

    @datafeedId = 1234

    @messages = []
    if startWithHelloWorldMessage
      @messages.push({
        id: '-sfAvIPTTmyrpORkBuvL_3___qulZoKedA'
        timestamp: @firstMessageTimestamp
        v2messageType: 'V2Message'
        streamId: @streamId
        message: '<messageML>Hello World</messageML>'
        fromUserId: @realUserId
      })

    nock.disableNetConnect()
    @authScope = nock(@host)
      .matchHeader('sessionToken', (val) -> !val?)
      .matchHeader('keyManagerToken', (val) -> !val?)
      .post('/sessionauth/v1/authenticate')
      .reply(200, {
        name: 'sessionToken'
        token: 'SESSION_TOKEN'
      })
      .post('/keyauth/v1/authenticate')
      .reply(200, {
        name: 'keyManagerToken'
        token: 'KEY_MANAGER_TOKEN'
      })
      .post('/agent/v1/util/echo')
      .reply(401, {
        code: 401
        message: 'Invalid session'
      })

    @podScope = nock(@host)
      .persist()
      .matchHeader('sessionToken', 'SESSION_TOKEN')
      .matchHeader('keyManagerToken', (val) -> !val?)
      .get('/pod/v1/sessioninfo')
      .reply(200, {
        userId: @botUserId
      })
      .get('/pod/v1/admin/user/' + @realUserId)
      .reply(200, {
        userAttributes: {
          emailAddress: 'johndoe@symphony.com'
          firstName: 'John'
          lastName: 'Doe'
          userName: 'johndoe'
          displayName: 'John Doe'
        }
        userSystemInfo: {
          id: @realUserId
        }
      })
      .get('/pod/v1/admin/user/' + @botUserId)
      .reply(200, {
        userAttributes: {
          emailAddress: 'mozart@symphony.com'
          firstName: 'Wolfgang Amadeus'
          lastName: 'Mozart'
          userName: 'mozart'
          displayName: 'Mozart'
        }
        userSystemInfo: {
          id: @realUserId
        }
      })

    @agentScope = nock(@host)
      .persist()
      .matchHeader('sessionToken', 'SESSION_TOKEN')
      .matchHeader('keyManagerToken', 'KEY_MANAGER_TOKEN')
      .post('/agent/v1/util/echo')
      .reply(200, (uri, requestBody) -> requestBody)
      .post('/agent/v2/stream/' + @streamId + '/message/create')
      .reply(200, (uri, requestBody) =>
        message = {
          id: uuid.v1()
          timestamp: new Date().valueOf()
          v2messageType: 'V2Message'
          streamId: @streamId
          message: requestBody.message
          attachments: []
          fromUserId: @botUserId
        }
        @_receiveMessage message
        message
      )
      .get('/agent/v2/stream/' + @streamId + '/message')
      .reply(200, (uri, requestBody) => JSON.stringify(@messages))
      .post('/agent/v1/datafeed/create')
      .reply(200, {
        id: @datafeedId
      })
      .get('/agent/v2/datafeed/' + @datafeedId + '/read')
      .reply (uri, requestBody) =>
        if @messages.length == 0
          [204, null]
        else
          copy = @messages
          @messages = []
          [200, JSON.stringify(copy)]

  close: () =>
    logger.info "Cleaning up nock for #{@host}"
    nock.cleanAll()

  _receiveMessage: (msg) =>
    @messages.push(msg)
    @emit 'received'

module.exports = NockServer