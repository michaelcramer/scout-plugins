require "time"
require "digest/md5"

# MongoDB Slow Queries Monitoring plug in for scout.
# Created by Jacob Harris, based on the MySQL slow queries plugin

class ScoutMongoSlow < Scout::Plugin
  needs "mongo"
  
  def enable_profiling(admin)
    # set to slow_only or higher (>100ms)
    if admin.profiling_level == :off
      admin.profiling_level = :slow_only
    end
  end
  
  def build_report
    database = option("database").to_s.strip
    if database.empty?
      return error( "A Mongo database name was not provided.",
                    "Slow query logging requires you to specify the database to profile." )
    end

    threshold_str = option("threshold").to_s.strip
    if threshold_str.empty?
      threshold = 100
    else
      threshold = threshold_str.to_i
    end

    db = Mongo::Connection.new.db(database)
    admin = db.admin
    
    enable_profiling(admin)
    
    slow_query_count = 0
    slow_queries = []
    last_run = memory(:last_run) || Time.now
    current_time = Time.now
    
    # info
    selector = { 'millis' => { '$gte' => threshold } }
    cursor = Mongo::Cursor.new(Mongo::Collection.new(db, Mongo::DB::SYSTEM_PROFILE_COLLECTION), :selector => selector).limit(20).sort([["$natural", "descending"]])
    
    # reads most recent first
    # {"ts"=>Wed Dec 16 02:44:03 UTC 2009, "info"=>"query twitter_follow.system.profile ntoreturn:0 reslen:1236 nscanned:8  \nquery: { query: { millis: { $gte: 5 } }, orderby: { $natural: -1 } }  nreturned:8 bytes:1220", "millis"=>57.0}
    cursor.each do |prof|
      ts = Time.parse(prof['ts'])
      break if ts < last_run
      
      slow_queries << prof
    end

    elapsed_seconds = current_time - last_run
    elapsed_seconds = 1 if elapsed_seconds < 1
    # calculate per-second
    report(:slow_queries => slow_queries.size/(elapsed_seconds/60.to_f))
    
    if slow_queries.any?
      alert(build_alert(slow_queries))
    end
    remember(:last_run,Time.now)
  rescue Mongo::MongoDBError => error
    error("A Mongo DB error has occurred.", "A Mongo DB error has occurred")    
  end
  
  def build_alert(slow_queries)
    subj = "Maximum Query Time exceeded on #{slow_queries.size} #{slow_queries.size > 1 ? 'queries' : 'query'}"
    
    body = String.new
    slow_queries.each do |sq|
      body << "<strong>#{sq["millis"]} millisec query on #{sq['ts']}:</strong>\n"
      body << sq['info']
      body << "\n\n"
    end # slow_queries.each
    {:subject => subj, :body => body}
  end # build_alert
end
