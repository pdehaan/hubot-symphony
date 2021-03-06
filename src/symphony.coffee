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

Log = require('log')
logger = new Log process.env.HUBOT_SYMPHONY_LOG_LEVEL or process.env.HUBOT_LOG_LEVEL or 'info'

fs = require 'fs'
request = require 'request'
Q = require 'q'
memoize = require 'memoizee'

class Symphony

  constructor: (@host, @privateKey, @publicKey, @passphrase) ->
    logger.info "Connecting to #{@host}"
    # refresh tokens on a weekly basis
    weeklyRefresh = memoize @_httpPost, {maxAge: 604800000, length: 1}
    @sessionAuth = => weeklyRefresh '/sessionauth/v1/authenticate'
    @keyAuth = => weeklyRefresh '/keyauth/v1/authenticate'
    Q.all([@sessionAuth(), @keyAuth()]).then (values) =>
      logger.info "Initialising with sessionToken: #{values[0].token} and keyManagerToken: #{values[1].token}"

  echo: (body) =>
    @_httpAgentPost('/agent/v1/util/echo', body)

  whoAmI: =>
    @_httpPodGet('/pod/v1/sessioninfo')

  getUser: (userId) =>
    @_httpPodGet('/pod/v1/admin/user/' + userId)

  sendMessage: (streamId, message, format) =>
    body = {
      message: message
      format: format
    }
    @_httpAgentPost('/agent/v2/stream/' + streamId + '/message/create', body)

  getMessages: (streamId, since, limit = 100) =>
    @_httpAgentGet('/agent/v2/stream/' + streamId + '/message')

  createDatafeed: =>
    @_httpAgentPost('/agent/v1/datafeed/create')

  readDatafeed: (datafeedId) =>
    @_httpAgentGet('/agent/v2/datafeed/' + datafeedId + '/read')

  _httpPodGet: (path, body) =>
    @sessionAuth().then (value) =>
      headers = {
        sessionToken: value.token
      }
      @_httpGet(path, headers)

  _httpAgentGet: (path, body) =>
    Q.all([@sessionAuth(), @keyAuth()]).then (values) =>
      headers = {
        sessionToken: values[0].token
        keyManagerToken: values[1].token
      }
      @_httpGet(path, headers)

  _httpAgentPost: (path, body) =>
    Q.all([@sessionAuth(), @keyAuth()]).then (values) =>
      headers = {
        sessionToken: values[0].token
        keyManagerToken: values[1].token
      }
      @_httpPost(path, headers, body)

  _httpGet: (path, headers = {}) =>
    @_httpRequest('GET', path, headers)

  _httpPost: (path, headers = {}, body) =>
    @_httpRequest('POST', path, headers, body)

  _httpRequest: (method, path, headers, body) =>
    deferred = Q.defer()
    options = {
      baseUrl: 'https://' + @host
      url: path
      json: true
      headers: headers
      method: method
      key: fs.readFileSync(@privateKey)
      cert: fs.readFileSync(@publicKey)
      passphrase: @passphrase
    }
    if body?
      options.body = body

    request(options, (err, res, data) =>
      if err?
        logger.warning "received #{res?.statusCode} error response from #{path}: #{err}"
        deferred.reject(new Error(err))
      else
        logger.debug "received #{res?.statusCode} response from #{path}: #{JSON.stringify(data)}"
        deferred.resolve data
    )
    deferred.promise

module.exports = Symphony