angular.module('collabjs.services')
  .service('postsService', ['$http', '$q', '$sce', function ($http, $q, $sce) {
    'use strict';

    function processHtmlContent(items, youtube) {
      if (!items) { return items; }

      var array = Array.isArray(items);
      if (!array) {
        items = [items];
      }

      for (var i = 0; i < items.length; i++) {
        var entry = items[i];
        if (entry.content) {
          entry.html = $sce.trustAsHtml(entry.content.twitterize(youtube));
        }
      }

      return array ? items : items[0];
    }

    return {
      processHtmlContent: processHtmlContent,
      getNews: function (topId) {
        var d = $q.defer()
          , options = { headers: { 'last-known-id': topId } };

        $http
          .get('/api/news', options)
          .success(function (data) {
            d.resolve(processHtmlContent(data || [], true));
          });
        return d.promise;
      },
      getNewsUpdatesCount: function (topId) {
        var d = $q.defer()
          , options = {
            headers: {
              'last-known-id': topId,
              'retrieve-mode': 'count-updates'
            }
          };
        $http
          .get('/api/news', options)
          .success(function (data) { d.resolve(data.posts || 0); })
          .error(function () { d.resolve(0); });
        return d.promise;
      },
      getNewsUpdates: function (topId) {
        var d = $q.defer()
          , options = {
            headers: {
              'last-known-id': topId,
              'retrieve-mode': 'get-updates'
            }
          };
        $http
          .get('/api/news', options)
          .success(function (data) { d.resolve(processHtmlContent(data, true)); });
        return d.promise;
      },
      getWall: function (account, topId) {
        var d = $q.defer()
          , query = '/api/u/' + account + '/posts'
          , options = { headers: { 'last-known-id': topId } };
        $http
          .get(query, options)
          .success(function (data) {
            if (data) {
              data.feed = processHtmlContent(data.feed, true);
            }
            d.resolve(data);
          })
          .error(function (data) { d.reject(data); });
        return d.promise;
      },
      getPostById: function (postId) {
        var d = $q.defer()
          , query = '/api/posts/' + postId;
        $http
          .get(query)
          .success(function (res) { d.resolve(processHtmlContent(res, true)); })
          .error(function (data) { d.reject(data); });
        return d.promise;
      },
      getPostsByTag: function (tag, topId) {
        var d = $q.defer()
          , options = { headers: { 'last-known-id': topId } };
        $http
          .get('/api/explore/' + tag, options)
          .success(function (data) { d.resolve(processHtmlContent(data, true)); });
        return d.promise;
      },
      getPostComments: function (postId) {
        var d = $q.defer();
        $http
          .get('/api/posts/' + postId + '/comments')
          .success(function (data) { d.resolve(processHtmlContent(data)); });
        return d.promise;
      },
      createPost: function (content) {
        var d = $q.defer();
        $http
          .post('/api/u/posts', { content: content })
          .then(function (res) { d.resolve(processHtmlContent(res.data, true)); });
        return d.promise;
      },
      addComment: function (postId, content) {
        var d = $q.defer();
        $http
          .post('/api/posts/' + postId + '/comments', { content: content })
          .then(function (res) { d.resolve(processHtmlContent(res.data)); });
        return d.promise;
      },
      deleteNewsPost: function (postId) {
        var d = $q.defer();
        $http
          .delete('/api/news/' + postId)
          .then(function (res) { d.resolve(res); });
        return d.promise;
      },
      deleteWallPost: function (postId) {
        var d = $q.defer();
        $http
          .delete('/api/posts/' + postId)
          .then(function (res) { d.resolve(res); });
        return d.promise;
      },
      loadPostComments: function (post) {
        var d = $q.defer();
        if (post && post.id) {
          $http
            .get('/api/posts/' + post.id + '/comments').success(function (data) {
              // TODO: ensure post exists
              post.comments = processHtmlContent(data);
              d.resolve(post);
            });
        } else {
          d.reject();
        }
        return d.promise;
      },
      /**
       * Locks post content and disables commenting.
       * @param {number} postId Post id.
       * @returns {promise} Deferred promise.
       */
      lockPost: function (postId) {
        var d = $q.defer();
        $http
          .post('/api/posts/' + postId + '/lock')
          .then(function () { d.resolve(true); });
        return d.promise;
      },
      /**
       * Unlocks post content and enables commenting.
       * @param {number} postId Post id.
       * @returns {promise} Deferred promise.
       */
      unlockPost: function (postId) {
        var d = $q.defer();
        $http
          .delete('/api/posts/' + postId + '/lock')
          .then(function () { d.resolve(true); });
        return d.promise;
      },
      /**
       * Add like for the given post.
       * @param postId Post id.
       */
      addLike: function (postId) {
        // TODO: get most recent number of likes with result
        var d = $q.defer();
        $http
          .post('/api/posts/' + postId + '/like')
          .then(function () { d.resolve(true); });
        return d.promise;
      },
      /**
       * Removes previously assigned like for the given post.
       * @param postId Post id.
       */
      removeLike: function (postId) {
        // TODO: get most recent number of likes with result
        var d = $q.defer();
        $http
          .delete('/api/posts/' + postId + '/like')
          .then(function () { d.resolve(true); });
        return d.promise;
      }
    };
  }]);