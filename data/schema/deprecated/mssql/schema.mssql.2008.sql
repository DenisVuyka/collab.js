-- v.0.3.1

CREATE DATABASE [collabjs]
GO

USE [collabjs]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[add_comment]
	@userId int,
  @postId int,
  @created datetime,
  @content nvarchar(max)
AS
BEGIN
  DECLARE @ID int;
	SET NOCOUNT ON;

  INSERT INTO comments (userId, postId, created, content) 
    VALUES (@userId, @postId, @created, @content);

  SELECT @ID = SCOPE_IDENTITY();

  UPDATE [posts] SET commentsCount = commentsCount + 1 WHERE id = @postId;

  IF @@ERROR <> 0
    BEGIN
      ROLLBACK TRANSACTION
      SET @ID = 0;
    END
  ELSE
    COMMIT TRANSACTION

  SELECT @ID AS insertId;
END
GO

CREATE PROCEDURE [dbo].[create_account]
  @account nvarchar(50),
  @name nvarchar(50),
  @password varchar(128),
  @email varchar(256),
  @emailHash varchar(32)
AS
BEGIN
  SET NOCOUNT ON;

  INSERT INTO users (account, name, password, email, emailHash)
    VALUES (@account, @name, @password, @email, @emailHash);

  SELECT SCOPE_IDENTITY() AS insertId;
END
GO

CREATE PROCEDURE [dbo].[follow_account]
	@originatorId int,
  @targetAccount varchar(50)
AS
BEGIN
	SET NOCOUNT ON;

  DECLARE @targetId int;
  DECLARE @userAccount varchar(50);

  SELECT @targetId = u.id FROM users AS u  WHERE u.account = @targetAccount;
  SELECT @userAccount = account FROM users WHERE id = @originatorId;

  IF NOT EXISTS
    (
      SELECT s.id FROM subscriptions AS s
        WHERE s.userId = @originatorId AND s.targetUserId = @targetId
    )
    BEGIN
      INSERT INTO subscriptions (userId, userAccount, targetUserId, targetAccount)
        VALUES (@originatorId, @userAccount, @targetId, @targetAccount);
      UPDATE users SET following = following + 1 WHERE id = @originatorId;
      UPDATE users SET followers = followers + 1 WHERE id = @targetId;
    END
  END
GO

CREATE PROCEDURE [dbo].[get_account]
	@account nvarchar(50)
AS
BEGIN
	SET NOCOUNT ON;
  SELECT TOP 1 *, emailHash as pictureId, dbo.get_user_roles(id) AS roles
    FROM users
  WHERE account = @account
END
GO

CREATE PROCEDURE [dbo].[get_account_by_id]
	@id int
AS
BEGIN
	SET NOCOUNT ON;
  SELECT TOP 1 *, emailHash as pictureId, dbo.get_user_roles(id) AS roles
    FROM users
  WHERE id = @id
END
GO

CREATE PROCEDURE [dbo].[get_comments]
	@postId int
AS
BEGIN
	SET NOCOUNT ON;
  SELECT c.*, u.account, u.name, u.emailHash as pictureId
  FROM comments AS c 
	  LEFT JOIN users AS u ON u.id = c.userId 
  WHERE c.postId = @postId
  ORDER BY created ASC;
END
GO

CREATE PROCEDURE [dbo].[get_followers]
	@originatorId int,
  @targetAccount varchar(50),
  @topId int,
  @limit int = 20
AS
BEGIN
	SET NOCOUNT ON;

  DECLARE @targetId INT;
  SELECT @targetId = id FROM users WHERE account = @targetAccount;

  SELECT TOP (@limit) result.* FROM
  (
    SELECT
	    u.id, u.account, u.name, u.website, u.location, u.bio, u.emailHash as pictureId,
	    u.posts, u.following, u.followers,
      (CASE @originatorId
			  WHEN u.id THEN CAST(1 as bit)
			  ELSE CAST(0 as bit)
			  END) AS isOwnProfile,
      (SELECT
				CASE 
					WHEN COUNT(sub.id) >0 THEN CAST(1 as bit)
					ELSE CAST(0 as bit)
				END
			  FROM subscriptions AS sub
			  WHERE sub.userId = @originatorId AND sub.targetAccount = u.account
			  GROUP BY sub.id) AS isFollowed
    FROM subscriptions AS s
	    LEFT JOIN users AS u ON u.id = s.userId
    WHERE s.targetUserId = @targetId 
	    AND EXISTS (select id from users where id = @topId OR @topId = 0)
  ) AS result
  WHERE (@topId <= 0 OR result.id > @topId);
END
GO

CREATE PROCEDURE [dbo].[get_following]
	@originatorId int,
  @targetAccount varchar(50),
  @topId int,
  @limit int = 20
AS
BEGIN
	SET NOCOUNT ON;

  DECLARE @targetId INT;
  SELECT @targetId = id FROM users WHERE account = @targetAccount;

  SELECT TOP (@limit) result.* FROM
  (
    SELECT
	    u.id, u.account, u.name, u.website, u.location, u.bio, u.emailHash as pictureId,
	    u.posts, u.following, u.followers,
      (CASE @originatorId
			  WHEN u.id THEN CAST(1 AS BIT)
			  ELSE CAST(0 AS BIT)
			  END) AS isOwnProfile,
      (SELECT
				CASE 
					WHEN COUNT(sub.id) > 0 THEN CAST(1 AS BIT)
					ELSE CAST(0 AS BIT)
				END
			  FROM subscriptions AS sub
			  WHERE sub.userId = @originatorId AND sub.targetAccount = u.account
			  GROUP BY sub.id) AS isFollowed
    FROM subscriptions AS s
	    LEFT JOIN users AS u ON u.id = s.targetUserId
    WHERE s.userId = @targetId 
	    AND EXISTS (SELECT id FROM users WHERE id = @topId OR @topId = 0)
  ) AS result
  WHERE (@topId <= 0 OR result.id > @topId);
END
GO

CREATE PROCEDURE [dbo].[get_main_timeline]
  @originatorId int,
  @topId int,
  @limit int = 20
AS
BEGIN
  SET NOCOUNT ON;

  SELECT TOP (@limit) result.* FROM
  (
    SELECT p.*, u.name, u.account, u.emailHash as pictureId
    FROM posts AS p
	    LEFT JOIN users AS u ON u.id = p.userId
    WHERE p.userId IN (
	    SELECT s.targetUserId FROM subscriptions AS s
	    WHERE s.userId = @originatorId AND s.isBlocked = 0
	    UNION SELECT @originatorId
    )
    AND NOT EXISTS (SELECT id FROM hidden_posts WHERE userId = @originatorId AND postId = p.id)
    AND EXISTS (SELECT id FROM posts WHERE id = @topId OR @topId = 0)
  ) AS result
  WHERE (@topId <= 0 OR result.id < @topId)
  ORDER BY result.created DESC
END
GO

CREATE PROCEDURE [dbo].[get_mentions]
  @originatorId int,
	@originatorAccount varchar(50),
  @topId int,
  @limit int = 20
AS
BEGIN
	SET NOCOUNT ON;

  DECLARE @term varchar(51);
  SET @term = '%@' + @originatorAccount + '%';

  SELECT TOP (@limit) result.* FROM
  (
    SELECT p.*, u.name, u.account, u.emailHash AS pictureId
    FROM posts AS p
	    LEFT JOIN users AS u ON u.id = p.userId
    WHERE u.account != @originatorAccount AND p.content LIKE @term
    AND NOT EXISTS (SELECT id FROM hidden_posts WHERE userId = @originatorId AND postId = p.id)
    AND EXISTS (SELECT id FROM posts WHERE id = @topId OR @topId = 0)
  ) AS result
  WHERE (@topId <= 0 OR result.id < @topId)
  ORDER BY result.created DESC
END
GO

CREATE PROCEDURE [dbo].[get_people]
	@originatorId int,
  @topId int,
  @limit int = 20
AS
BEGIN
	SET NOCOUNT ON;

  SELECT TOP (@limit) result.* FROM
  (
    SELECT u.id, u.account, u.name, u.website, u.location, u.bio,
      u.created, u.emailHash AS pictureId,
      u.posts, u.following, u.followers,
      (SELECT
				CASE 
					WHEN COUNT(sub.id) >0 THEN CAST(1 AS bit)
					ELSE CAST(0 AS bit)
				END
			  FROM subscriptions AS sub
			  WHERE sub.userId = @originatorId AND sub.targetAccount = u.account
			  GROUP BY sub.id) AS isFollowed,
		  (CASE @originatorId
			  WHEN u.id THEN CAST(1 AS BIT)
			  ELSE CAST(0 AS BIT)
			  END) AS isOwnProfile
    FROM users AS u
    WHERE EXISTS (SELECT id FROM users WHERE id = @topId OR @topId = 0)
    ) AS result
  WHERE (@topId <= 0 OR result.id > @topId)
  ORDER BY result.created
END
GO

CREATE PROCEDURE [dbo].[get_post] 
	@postId int
AS
BEGIN
	SET NOCOUNT ON;
  SELECT TOP (1) p.*, u.name, u.account, u.emailHash AS pictureId
  FROM posts AS p
	  LEFT JOIN users AS u ON u.id = p.userId
  WHERE p.id = @postId;
END
GO

CREATE PROCEDURE [dbo].[get_post_author]
	@postId int
AS
BEGIN
	SET NOCOUNT ON;

  SELECT TOP (1) u.id, u.account, u.name, u.email, u.emailHash AS pictureId
  FROM posts AS p
    LEFT JOIN users AS u ON u.id = p.userId
  WHERE p.id = @postId
END
GO

CREATE PROCEDURE [dbo].[get_public_profile]
	@caller varchar(50),
  @target varchar(50)
AS
BEGIN
	SET NOCOUNT ON;

  SELECT u.id, u.account, u.name, u.website, u.bio, u.emailHash AS pictureId, u.location,
    u.posts, u.following, u.followers,
    (SELECT
	    CASE
			  WHEN COUNT(sub.id) >0 THEN CAST(1 AS bit)
				ELSE CAST(0 AS bit)
			END
			FROM subscriptions AS sub
			WHERE sub.userAccount = @caller AND sub.targetAccount = u.account
			GROUP BY sub.id) AS isFollowed
  FROM users AS u
  WHERE u.account = @target
END
GO

CREATE PROCEDURE [dbo].[get_timeline]
  @originatorId int,
  @targetAccount varchar(50),
  @topId int,
  @limit int = 20
AS
BEGIN
	SET NOCOUNT ON;

  SELECT TOP (@limit) result.* FROM
  (
    SELECT p.*, u.name, u.account, u.emailHash AS pictureId
    FROM posts AS p
	    LEFT JOIN users AS u ON u.id = p.userId
    WHERE u.account = @targetAccount
      AND NOT EXISTS (SELECT id FROM hidden_posts WHERE userId = @originatorId AND postId = p.id)
      AND EXISTS (SELECT id FROM posts WHERE userId = p.userId AND (id = @topId OR @topId = 0))
  ) AS result
  WHERE (@topId <= 0 OR result.id < @topId)
  ORDER BY result.created DESC
END
GO

CREATE PROCEDURE [dbo].[get_timeline_updates] 
	@originatorId int,
  @topId int
AS
BEGIN
	SET NOCOUNT ON;

  SELECT result.* FROM
  (
    SELECT p.*, u.name, u.account, u.emailHash AS pictureId
    FROM posts AS p
	    LEFT JOIN users AS u ON u.id = p.userId
    WHERE p.userId IN (
	    SELECT s.targetUserId FROM subscriptions AS s
	    WHERE s.userId = @originatorId AND s.isBlocked = 0
	    UNION SELECT @originatorId
    )
  ) AS result
  WHERE result.id > @topId AND @topId > 0
  ORDER BY result.created ASC;
END
GO

CREATE PROCEDURE [dbo].[get_timeline_updates_count]
	@originatorId int,
  @topId int
AS
BEGIN
	SET NOCOUNT ON;

  SELECT COUNT(id) AS posts FROM (
    SELECT p.id
    FROM posts AS p
    WHERE p.userId IN (
      SELECT s.targetUserId FROM subscriptions AS s
      WHERE s.userId = @originatorId AND s.isBlocked = 0
      UNION SELECT @originatorId
      )
  ) AS result
  WHERE id > @topId AND @topId > 0
END
GO

CREATE PROCEDURE [dbo].[unfollow_account] 
	@originatorId int,
  @targetAccount varchar(50)
AS
BEGIN
	SET NOCOUNT ON;

  DECLARE @targetId INT;
  SELECT @targetId = u.id FROM users AS u  WHERE u.account = @targetAccount;

  DELETE FROM subscriptions WHERE userId = @originatorId AND targetUserId = @targetId;
  IF @@ROWCOUNT > 0
  BEGIN
    UPDATE users SET following = following - 1 WHERE id = @originatorId;
    UPDATE users SET followers = followers - 1 WHERE id = @targetId;
  END
END
GO

CREATE FUNCTION [dbo].[get_user_roles] 
(
	@userId int
)
RETURNS nvarchar(max)
AS
BEGIN
  DECLARE @result nvarchar(max)

  SELECT @result = COALESCE(@result + ',','') + r.loweredName
  FROM roles AS r, user_roles AS ur
  WHERE r.id = ur.roleId AND ur.userId = @userId
  ORDER BY r.loweredName;

	RETURN COALESCE(@result, '');
END
GO

CREATE TABLE [dbo].[comments](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[userId] [int] NOT NULL,
	[postId] [int] NOT NULL,
	[created] [datetime] NOT NULL,
	[content] [nvarchar](max) NOT NULL,
 CONSTRAINT [PK_comments] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[posts](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[userId] [int] NOT NULL,
	[content] [nvarchar](max) NOT NULL,
	[created] [datetime] NOT NULL,
	[commentsCount] [int] NOT NULL,
 CONSTRAINT [PK_posts] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[hidden_posts](
  [id] [int] IDENTITY(1,1) NOT NULL,
  [userId] [int] NOT NULL,
  [postId] [int] NOT NULL,
  CONSTRAINT [PK_hidden_posts] PRIMARY KEY CLUSTERED
(
  [id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[search_lists](
  [id] [int] IDENTITY(1,1) NOT NULL,
  [name] [nvarchar](45) NOT NULL,
  [userId] [int] NOT NULL,
  [query] [nvarchar](max) NOT NULL,
  [source] [nvarchar](45) NOT NULL,
CONSTRAINT [PK_search_lists] PRIMARY KEY CLUSTERED
(
  [id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


CREATE TABLE [dbo].[roles](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[name] [nvarchar](256) NOT NULL,
	[loweredName] [nvarchar](256) NOT NULL,
 CONSTRAINT [PK_roles] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[subscriptions](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[userId] [int] NOT NULL,
	[userAccount] [varchar](50) NOT NULL,
	[targetUserId] [int] NOT NULL,
	[targetAccount] [varchar](50) NOT NULL,
	[isBlocked] [bit] NOT NULL,
 CONSTRAINT [PK_subscriptions] PRIMARY KEY CLUSTERED
(
	[userId] ASC,
	[targetUserId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[user_roles](
	[userId] [int] NOT NULL,
	[roleId] [int] NOT NULL,
 CONSTRAINT [PK_user_role] PRIMARY KEY CLUSTERED 
(
	[userId] ASC,
	[roleId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE TABLE [dbo].[users](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[account] [varchar](50) NOT NULL,
	[name] [nvarchar](50) NOT NULL,
	[created] [datetime] NOT NULL,
	[password] [varchar](128) NOT NULL,
	[email] [varchar](256) NOT NULL,
	[emailHash] [varchar](32) NOT NULL,
	[location] [nvarchar](50) NULL,
	[website] [nvarchar](256) NULL,
	[bio] [nvarchar](160) NULL,
	[posts] [int] NOT NULL,
	[comments] [int] NOT NULL,
	[following] [int] NOT NULL,
  [followers] [int] NOT NULL,
 CONSTRAINT [PK_id] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE UNIQUE NONCLUSTERED INDEX [IX_subscriptions_id] ON [dbo].[subscriptions]
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO

CREATE NONCLUSTERED INDEX [ix_role] ON [dbo].[user_roles]
(
	[roleId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO

CREATE UNIQUE NONCLUSTERED INDEX [IX_account] ON [dbo].[users] ([account] ASC)
  WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO

ALTER TABLE [dbo].[comments] ADD  CONSTRAINT [DF_comments_created]  DEFAULT (getutcdate()) FOR [created]
GO
ALTER TABLE [dbo].[posts] ADD  CONSTRAINT [DF_posts_created]  DEFAULT (getutcdate()) FOR [created]
GO
ALTER TABLE [dbo].[subscriptions] ADD  CONSTRAINT [DF_subscriptions_isBlocked]  DEFAULT ((0)) FOR [isBlocked]
GO

ALTER TABLE [dbo].[users] ADD  CONSTRAINT [DF_users_created] DEFAULT (getutcdate()) FOR [created]
GO
ALTER TABLE [dbo].[users] ADD  CONSTRAINT [DF_users_emailHash] DEFAULT ('00000000000000000000000000000000') FOR [emailHash]
GO
ALTER TABLE [dbo].[users] ADD  CONSTRAINT [DF_users_posts]  DEFAULT ((0)) FOR [posts]
GO
ALTER TABLE [dbo].[users] ADD  CONSTRAINT [DF_users_comments]  DEFAULT ((0)) FOR [comments]
GO
ALTER TABLE [dbo].[users] ADD  CONSTRAINT [DF_users_following]  DEFAULT ((0)) FOR [following]
GO
ALTER TABLE [dbo].[users] ADD  CONSTRAINT [DF_users_followers]  DEFAULT ((0)) FOR [followers]
GO

ALTER TABLE [dbo].[comments]  WITH CHECK ADD  CONSTRAINT [FK_comments_post] FOREIGN KEY([postId])
REFERENCES [dbo].[posts] ([id]) ON DELETE CASCADE
GO
ALTER TABLE [dbo].[comments] CHECK CONSTRAINT [FK_comments_post]
GO
ALTER TABLE [dbo].[comments]  WITH CHECK ADD  CONSTRAINT [FK_comments_user] FOREIGN KEY([userId])
REFERENCES [dbo].[users] ([id])
GO
ALTER TABLE [dbo].[comments] CHECK CONSTRAINT [FK_comments_user]
GO

ALTER TABLE [dbo].[posts]  WITH CHECK ADD  CONSTRAINT [FK_posts_user] FOREIGN KEY([userId])
REFERENCES [dbo].[users] ([id]) ON DELETE CASCADE
GO
ALTER TABLE [dbo].[posts] CHECK CONSTRAINT [FK_posts_user]
GO
ALTER TABLE [dbo].[posts] ADD  CONSTRAINT [DF_posts_commentsCount]  DEFAULT ((0)) FOR [commentsCount]
GO

ALTER TABLE [dbo].[subscriptions]  WITH CHECK ADD  CONSTRAINT [FK_subscriptions_targetUserId] FOREIGN KEY([targetUserId])
REFERENCES [dbo].[users] ([id])
GO
ALTER TABLE [dbo].[subscriptions] CHECK CONSTRAINT [FK_subscriptions_targetUserId]
GO
ALTER TABLE [dbo].[subscriptions]  WITH CHECK ADD  CONSTRAINT [FK_subscriptions_userId] FOREIGN KEY([userId])
REFERENCES [dbo].[users] ([id])
GO
ALTER TABLE [dbo].[subscriptions] CHECK CONSTRAINT [FK_subscriptions_userId]
GO

ALTER TABLE [dbo].[user_roles]  WITH CHECK ADD  CONSTRAINT [FK_ur_role] FOREIGN KEY([roleId])
REFERENCES [dbo].[roles] ([id])
GO
ALTER TABLE [dbo].[user_roles] CHECK CONSTRAINT [FK_ur_role]
GO
ALTER TABLE [dbo].[user_roles]  WITH CHECK ADD  CONSTRAINT [FK_ur_user] FOREIGN KEY([userId])
REFERENCES [dbo].[users] ([id])
GO
ALTER TABLE [dbo].[user_roles] CHECK CONSTRAINT [FK_ur_user]
GO

CREATE PROCEDURE get_posts_by_hashtag
  @originatorId int,
  @query nvarchar(256),
  @topId int,
  @limit int = 20
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @hashtag VARCHAR(256);
  SET @hashtag = '%' + @query + '%';

  SELECT TOP (@limit) result.* FROM
  (
    SELECT p.*, u.name, u.account, u.emailHash as pictureId
    FROM posts AS p
	    LEFT JOIN users AS u ON u.id = p.userId
    WHERE p.content LIKE @hashtag
    AND NOT EXISTS (SELECT id FROM hidden_posts WHERE userId = @originatorId AND postId = p.id)
    AND EXISTS (select id from posts where id = @topId OR @topId = 0)
  ) AS result
  WHERE (@topId <= 0 OR result.id < @topId)
  ORDER BY result.created DESC
END
GO

IF NOT EXISTS (SELECT TOP 1 id from roles where loweredName = 'administrator')
BEGIN
  INSERT INTO roles (name, loweredName) VALUES ('Administrator', 'administrator')
END
GO

CREATE PROCEDURE [dbo].[add_post]
  @userId int,
  @content nvarchar(max),
  @created datetime
AS
BEGIN
  DECLARE @ID INT;
  SET NOCOUNT ON;
  BEGIN TRANSACTION

  INSERT INTO posts (userId, content, created)
    VALUES (@userId, @content, @created);

  SELECT @ID = SCOPE_IDENTITY();
  UPDATE [users] SET posts = posts + 1 WHERE id = @userId;

  IF @@ERROR <> 0
    BEGIN
      ROLLBACK TRANSACTION
      SET @ID = 0;
    END
  ELSE
    COMMIT TRANSACTION

  SELECT @ID AS insertId;
END
GO

CREATE PROCEDURE [dbo].[delete_post]
  @userId INT,
	@postId INT
AS
BEGIN
	SET NOCOUNT ON;
  DELETE FROM [posts] WHERE id = @postId AND userId = @userId;
  IF @@ROWCOUNT > 0
    BEGIN
      UPDATE [users] SET posts = posts - 1 WHERE id = @userId;
    END
  ELSE
    BEGIN
      IF NOT EXISTS (SELECT TOP 1 FROM hidden_posts WHERE userId = @userId AND postId = @postId)
        BEGIN
          INSERT INTO hidden_posts (userId, postId) VALUES (@userId, @postId)
        END
    END
END
GO

CREATE PROCEDURE [dbo].[add_search_list]
  @name nvarchar(45),
  @userId int,
  @query nvarchar(max),
  @source nvarchar(45)
AS
BEGIN
  IF NOT EXISTS (SELECT id FROM search_lists WHERE name = @name AND userId = @userId)
    BEGIN
      INSERT INTO search_lists (name, userId, query, source)
        VALUES (@name, @userId, @query, @source)
    END
END
GO

CREATE PROCEDURE [dbo].[get_search_lists]
  @userId int
AS
BEGIN
  SELECT name, query, source FROM search_lists WHERE userId = @userId
END
GO

CREATE PROCEDURE [dbo].[delete_search_list]
  @userId int,
  @name nvarchar(45)
AS
BEGIN
  DELETE FROM search_lists WHERE userId = @userId AND name = @name
END
GO