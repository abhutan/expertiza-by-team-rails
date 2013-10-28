#contains all functions related to management of the signup sheet for an assignment
#functions to add new topics to an assignment, edit properties of a particular topic, delete a topic, etc
#are included here

#A point to be taken into consideration is that :id (except when explicitly stated) here means topic id and not assignment id
#(this is referenced as :assignment id in the params has)
#The way it works is that assignments have their own id's, so do topics. A topic has a foreign key dependecy on the assignment_id
#Hence each topic has a field called assignment_id which points which can be used to identify the assignment that this topic belongs
#to

class SignUpSheetController < ApplicationController
  require 'rgl/adjacency'
  require 'rgl/dot'
  require 'graph/graphviz_dot'
  require 'rgl/topsort'

  #Includes functions for team management. Refer /app/helpers/ManageTeamHelper
  include ManageTeamHelper
  #Includes functions for Dead line management. Refer /app/helpers/DeadLineHelper
  include DeadlineHelper

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [:destroy, :create, :update],
    :redirect_to => {:action => :list}

  #This displays a page that lists all the available topics for an assignment.
  #Contains links that let an admin or Instructor edit, delete, view enrolled/waitlisted members for each topic
  #Also contains links to delete topics and modify the deadlines for individual topics. Staggered means that different topics
  #can have different deadlines.
  def add_signup_topics
    load_add_signup_topics(params[:id])

    if @assignment.staggered_deadline ==true

      @review_rounds = Assignment.find(params[:id]).get_review_rounds
      @topics = SignUpTopic.find_all_by_assignment_id(params[:id])

      #Function call to set up due dates
      assignment_due_date

      #Render a view different from the add_sign_up.html.erb  , so rendering a view for staggered deadlines.
      render "add_signup_topics_staggered"

    end
  end

  def assignment_due_date
       #Use this until you figure out how to initialize this array
    @duedates = SignUpTopic.find_by_sql("SELECT s.id as topic_id FROM sign_up_topics s WHERE s.assignment_id = " + params[:id].to_s)

    if !@topics.nil?
      i=0
      @topics.each { |topic|

        @duedates[i]['t_id'] = topic.id
        @duedates[i]['topic_identifier'] = topic.topic_identifier
        @duedates[i]['topic_name'] = topic.topic_name

        for j in 1..@review_rounds
          if j == 1
            duedate_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('submission').id)
            duedate_rev = TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('review').id)
          else
            duedate_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(topic.id, DeadlineType.find_by_name('resubmission').id, j)
            duedate_rev = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(topic.id, DeadlineType.find_by_name('rereview').id, j)
          end
          if !duedate_subm.nil? && !duedate_rev.nil?
            @duedates[i]['submission_'+ j.to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
            @duedates[i]['review_'+ j.to_s] = DateTime.parse(duedate_rev['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
          else
            #the topic is new. so copy deadlines from assignment
            set_of_due_dates = DueDate.find_all_by_assignment_id(params[:id])
            set_of_due_dates.each { |due_date|
              create_topic_deadline(due_date, 0, topic.id)
            }
            # code execution would have hit the else part during review_round one. So we'll do only round one
            duedate_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('submission').id)
            duedate_rev = TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('review').id)
            @duedates[i]['submission_'+ j.to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
            @duedates[i]['review_'+ j.to_s] = DateTime.parse(duedate_rev['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
          end

        end
        duedate_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('metareview').id)
        if !duedate_subm.nil?
          @duedates[i]['submission_'+ (@review_rounds+1).to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
        else
          @duedates[i]['submission_'+ (@review_rounds+1).to_s] = nil
        end
        i = i + 1
      }

    end
  end

  #Seems like this function is similar to the above function> we are not quite sure what publishing rights mean. Seems like
  #the values for the last column in http://expertiza.ncsu.edu/student_task/list are sourced from here
  def view_publishing_rights
    load_add_signup_topics(params[:id])
  end

  #retrieves all the data associated with the given assignment. Includes all topics, 
  #participants(people who are doing this assignment) and signed up users (people who have chosen a topic (confirmed or waitlisted)
  def load_add_signup_topics(assignment_id)
    @id = assignment_id
    @sign_up_topics = SignUpTopic.find(:all, :conditions => ['assignment_id = ?', assignment_id])
    @slots_filled = SignUpTopic.find_slots_filled(assignment_id)
    @slots_waitlisted = SignUpTopic.find_slots_waitlisted(assignment_id)

    @assignment = Assignment.find(assignment_id)
    #ACS Removed the if condition (and corresponding else) which differentiate assignments as team and individual assignments
    # to treat all assignments as team assignments
    @participants = SignedUpUser.find_team_participants(assignment_id)
  end

  # Prepares the form for adding a new topic. Used in conjuntion with create
  def new
    @id = params[:id]
    @sign_up_topic = SignUpTopic.new
    @sign_up_topic.assignment = Assignment.find(params[:id])
    @topic = @sign_up_topic
  end

  #This method is used to create signup topics
  #In this code params[:id] is the assignment id and not topic id. The intuition is 
  #that assignment id will virtually be the signup sheet id as well as we have assumed 
  #that every assignment will have only one signup sheet
  def create
    topic = SignUpTopic.find_by_topic_name_and_assignment_id(params[:topic][:topic_name], params[:id])

    #if the topic already exists then update
    if topic != nil
      topic.topic_identifier = params[:topic][:topic_identifier]

      #While saving the max choosers you should be careful; if there are users who have signed up for this particular
      #topic and are on waitlist, then they have to be converted to confirmed topic based on the availability. But if
      #there are choosers already and if there is an attempt to decrease the max choosers, as of now I am not allowing
      #it.
      if SignedUpUser.find_by_topic_id(topic.id).nil? || topic.max_choosers == params[:topic][:max_choosers]
        topic.max_choosers = params[:topic][:max_choosers]
      else
        if topic.max_choosers.to_i < params[:topic][:max_choosers].to_i
          topic.update_waitlisted_users(params[:topic][:max_choosers])
          topic.max_choosers = params[:topic][:max_choosers]
        else
          flash[:error] = 'Value of maximum choosers can only be increased! No change has been made to max choosers.'
        end
      end

      topic.category = params[:topic][:category]
      #topic.assignment_id = params[:id] 
      topic.save
      redirect_to_sign_up(params[:id])
    else
      #set the values for the new topic and commit to database
      @sign_up_topic = SignUpTopic.new
      @sign_up_topic.topic_identifier = params[:topic][:topic_identifier]
      @sign_up_topic.topic_name = params[:topic][:topic_name]
      @sign_up_topic.max_choosers = params[:topic][:max_choosers]
      @sign_up_topic.category = params[:topic][:category]
      @sign_up_topic.assignment_id = params[:id]
      @assignment = Assignment.find(params[:id])

      if @assignment.is_microtask?
        @sign_up_topic.micropayment = params[:topic][:micropayment]
      end

=begin
      if @assignment.staggered_deadline?
        topic_set = Array.new
        topic = @sign_up_topic.id

      end
=end

      if @sign_up_topic.save
        #NotificationLimit.create(:topic_id => @sign_up_topic.id)
        flash[:notice] = 'Topic was successfully created.'
        redirect_to_sign_up(params[:id])
      else
        render :action => 'new', :id => params[:id]
      end
    end
  end

  #simple function that redirects t0 the /add_signup_topics or the /add_signup_topics_staggered page depending on assignment type
  #staggered means that different topics can have different deadlines.
  def redirect_to_sign_up(assignment_id)
    assignment = Assignment.find(assignment_id)
      redirect_to :action => 'add_signup_topics', :id => assignment_id
  end

  #This method is used to delete signup topics
  def delete
    @topic = SignUpTopic.find(params[:id])

    if !@topic.nil?
      @topic.destroy
    else
      flash[:error] = "Topic could not be deleted"
    end

    #if this assignment has staggered deadlines then destroy the dependencies as well    
    if Assignment.find(params[:assignment_id])['staggered_deadline'] == true
      dependencies = TopicDependency.find_all_by_topic_id(params[:id])
      if !dependencies.nil?
        dependencies.each { |dependency| dependency.destroy }
      end
    end
    redirect_to_sign_up(params[:assignment_id])
  end
  #prepares the page. shows the form which can be used to enter new values for the different properties of an assignment
  def edit
    @topic = SignUpTopic.find(params[:id])
    @assignment_id = params[:assignment_id]
  end

  #updates the database tables to reflect the new values for the assignment. Used in conjuntion with edit
  def update
    topic = SignUpTopic.find(params[:id])

    if !topic.nil?
      topic.topic_identifier = params[:topic][:topic_identifier]

      #While saving the max choosers you should be careful; if there are users who have signed up for this particular
      #topic and are on waitlist, then they have to be converted to confirmed topic based on the availability. But if
      #there are choosers already and if there is an attempt to decrease the max choosers, as of now I am not allowing
      #it.
      if SignedUpUser.find_by_topic_id(topic.id).nil? || topic.max_choosers == params[:topic][:max_choosers]
        topic.max_choosers = params[:topic][:max_choosers]
      else
        if topic.max_choosers.to_i < params[:topic][:max_choosers].to_i
          topic.update_waitlisted_users(params[:topic][:max_choosers])
          topic.max_choosers = params[:topic][:max_choosers]
        else
          flash[:error] = 'Value of maximum choosers can only be increased! No change has been made to max choosers.'
        end
      end
      #update tables
      topic.category = params[:topic][:category]
      topic.topic_name = params[:topic][:topic_name]
      topic.micropayment = params[:topic][:micropayment]
      topic.save
    else
      flash[:error] = "Topic could not be updated"
    end
    redirect_to_sign_up(params[:assignment_id])
  end

  def signup_topics
    @assignment_id = params[:id]
    @sign_up_topics = SignUpTopic.find(:all, :conditions => ['assignment_id = ?', params[:id]])
    @slots_filled = SignUpTopic.find_slots_filled(params[:id])
    @slots_waitlisted = SignUpTopic.find_slots_waitlisted(params[:id])
    @show_actions = true
    assignment=Assignment.find(params[:id])

    if assignment.due_dates.find_by_deadline_type_id(1)!= nil
      if !assignment.staggered_deadline? and assignment.due_dates.find_by_deadline_type_id(1).due_at < Time.now
        @show_actions = false
      end
    end

    #ACS Removed the if condition (and corresponding else) which differentiate assignments as team and individual assignments
    # to treat all assignments as team assignments
    users_team = SignedUpUser.find_team_users(params[:id],(session[:user].id))

    if users_team.size == 0
      @selected_topics = nil
    else
      #TODO: fix this; cant use 0
      @selected_topics = otherConfirmedTopicforUser(params[:id], users_team[0].t_id)
    end
  end


  #this function is used to delete a previous signup
  def delete_signup
    delete_signup_for_topic(params[:assignment_id], params[:id])
    redirect_to :action => 'signup_topics', :id => params[:assignment_id]
  end

  def delete_signup_for_topic(assignment_id, topic_id)
    #find whether assignment is team assignment
    assignment = Assignment.find(assignment_id)

    #making sure that the drop date deadline hasn't passed
    dropDate = DueDate.find(:first, :conditions => {:assignment_id => assignment.id, :deadline_type_id => '6'})
    if (!dropDate.nil? && dropDate.due_at < Time.now)
      flash[:error] = "You cannot drop this topic because the drop deadline has passed."
    else
      #if team assignment find the creator id from teamusers table and teams
      #ACS Removed the if condition (and corresponding else) which differentiate assignments as team and individual assignments
      # to treat all assignments as team assignments
      #users_team will contain the team id of the team to which the user belongs
      users_team = SignedUpUser.find_team_users(assignment_id,(session[:user].id))
      signup_record = SignedUpUser.find_by_topic_id_and_creator_id(topic_id, users_team[0].t_id)

      #if a confirmed slot is deleted then push the first waiting list member to confirmed slot if someone is on the waitlist
      if signup_record.is_waitlisted == false
        #find the first wait listed user if exists
        first_waitlisted_user = SignedUpUser.find_by_topic_id_and_is_waitlisted(topic_id, true)

        if !first_waitlisted_user.nil?
          # As this user is going to be allocated a confirmed topic, all of his waitlisted topic signups should be purged
          ### Bad policy!  Should be changed! (once users are allowed to specify waitlist priorities) -efg
          first_waitlisted_user.is_waitlisted = false
          first_waitlisted_user.save

          #update the participants details
          #ACS Removed the if condition (and corresponding else) which differentiate assignments as team and individual assignments
          # to treat all assignments as team assignments

          user_id = TeamsUser.find(:first, :conditions => {:team_id => first_waitlisted_user.creator_id}).user_id
          participant = Participant.find_by_user_id_and_parent_id(user_id,assignment.id)

          participant.update_topic_id(topic_id)

          SignUpTopic.cancel_all_waitlists(first_waitlisted_user.creator_id, assignment_id)
        end
      end

      if !signup_record.nil?
        participant = Participant.find_by_user_id_and_parent_id(session[:user].id, assignment_id)
        #update participant's topic id to nil
        participant.update_topic_id(nil)
        signup_record.destroy
      end
    end #end condition for 'drop deadline' check
  end

  def signup
    puts "++++++++++++++++++++++++++++"
    puts "you called me in sign_up_sheet_controller!"
    #find the assignment to which user is signing up
    assignment = Assignment.find(params[:assignment_id])

    #check whether team assignment. This is to decide whether a team_id or user_id should be the creator_id
    #Always use team_id ACS

    #check whether the user already has a team for this assignment
    users_team = SignedUpUser.find_team_users(params[:assignment_id],(session[:user].id))
    if users_team.size == 0
      #if team is not yet created, create new team.
      team = AssignmentTeam.create_team_and_node(params[:assignment_id])
      user = User.find(session[:user].id)
      teamuser = create_team_users(user, team.id)
      confirmationStatus = confirmTopic(team.id, params[:id], params[:assignment_id])
    else
      confirmationStatus = confirmTopic(users_team[0].t_id, params[:id], params[:assignment_id])
    end

    redirect_to :action => 'signup_topics', :id => params[:assignment_id]
  end



  # When using this method when creating fields, update race conditions by using db transactions
  def slotAvailable?(topic_id)
    SignUpTopic.slotAvailable?(topic_id)
  end

  def otherConfirmedTopicforUser(assignment_id, creator_id)
    user_signup = SignedUpUser.find_user_signup_topics(assignment_id, creator_id)
    user_signup
  end

  def confirmTopic(creator_id, topic_id, assignment_id)
    #check whether user has signed up already
    user_signup = otherConfirmedTopicforUser(assignment_id, creator_id)

    sign_up = SignedUpUser.new
    sign_up.topic_id = params[:id]
    sign_up.creator_id = creator_id
    result = false
    if user_signup.size == 0

      # Using a DB transaction to ensure atomic inserts
      ActiveRecord::Base.transaction do
        #check whether slots exist (params[:id] = topic_id) or has the user selected another topic
        if slotAvailable?(topic_id)
          sign_up.is_waitlisted = false

          #Update topic_id in participant table with the topic_id
          participant = Participant.find_by_user_id_and_parent_id(session[:user].id, assignment_id)

          participant.update_topic_id(topic_id)
        else
          sign_up.is_waitlisted = true
        end
        if sign_up.save
          result = true
        end
      end
    else
      #If all the topics choosen by the user are waitlisted,
      for user_signup_topic in user_signup
        if user_signup_topic.is_waitlisted == false
          flash[:error] = "You have already signed up for a topic."
          return false
        end
      end

      # Using a DB transaction to ensure atomic inserts
      ActiveRecord::Base.transaction do
        #check whether user is clicking on a topic which is not going to place him in the waitlist
        if !slotAvailable?(topic_id)
          sign_up.is_waitlisted = true
          if sign_up.save
            result = true
          end
        else
          #if slot exist, then confirm the topic for the user and delete all the waitlist for this user        
          SignUpTopic.cancel_all_waitlists(creator_id, assignment_id)
          sign_up.is_waitlisted = false
          sign_up.save
          participant = Participant.find_by_user_id_and_parent_id(session[:user].id, assignment_id)
          participant.update_topic_id(topic_id)
          result = true
        end
      end
    end

    result
  end

  def has_user(user, team_id)
    if TeamsUser.find_by_team_id_and_user_id(team_id, user.id)
      return true
    else
      return false
    end
  end

  #this function is used to prevent injection attacks.  A topic *dependent* on another topic cannot be
  # attempted until the other topic has been completed..
  def save_topic_dependencies
    # Prevent injection attacks - we're using this in a system() call later
    params[:assignment_id] = params[:assignment_id].to_i.to_s

    topics = SignUpTopic.find_all_by_assignment_id(params[:assignment_id])
    topics = topics.collect { |topic|
      #if there is no dependency for a topic then there wont be a post for that tag.
      #if this happens store the dependency as "0"
      if !params['topic_dependencies_' + topic.id.to_s].nil?
        [topic.id, params['topic_dependencies_' + topic.id.to_s][:dependent_on]]
      else
        [topic.id, ["0"]]
      end
    }

    # Save the dependency in the topic dependency table
    TopicDependency.save_dependency(topics)

    node = 'id'
    dg = build_dependency_graph(topics, node)

    if dg.acyclic?
      #This method produces sets of vertexes which should have common start time/deadlines
      set_of_topics = create_common_start_time_topics(dg)
      set_start_due_date(params[:assignment_id], set_of_topics)
      @top_sort = dg.topsort_iterator.to_a
    else
      flash[:error] = "There may be one or more cycles in the dependencies. Please correct them"
    end


    node = 'topic_name'
    dg = build_dependency_graph(topics, node) # rebuild with new node name

    graph_output_path = 'public/images/staggered_deadline_assignment_graph'
    FileUtils::mkdir_p graph_output_path
    dg.write_to_graphic_file('jpg', "#{graph_output_path}/graph_#{params[:assignment_id]}")

    redirect_to_sign_up(params[:assignment_id])
  end


  #If the instructor needs to explicitly change the start/due dates of the topics 
  #This is true in case of a staggered deadline type assignment. Individual deadlines can 
  # be set on a per topic  and per round basis
  def save_topic_deadlines

    due_dates = params[:due_date]

    review_rounds = Assignment.find(params[:assignment_id]).get_review_rounds
    due_dates.each { |due_date|
      for i in 1..review_rounds
        if i == 1
          topic_deadline_type_subm = DeadlineType.find_by_name('submission').id
          topic_deadline_type_rev = DeadlineType.find_by_name('review').id
        else
          topic_deadline_type_subm = DeadlineType.find_by_name('resubmission').id
          topic_deadline_type_rev = DeadlineType.find_by_name('rereview').id
        end

        topic_deadline_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(due_date['t_id'].to_i, topic_deadline_type_subm, i)
        topic_deadline_subm.update_attributes({'due_at' => due_date['submission_' + i.to_s]})
        flash[:error] = "Please enter a valid " + (i > 1 ? "Resubmission deadline " + (i-1).to_s : "Submission deadline") if topic_deadline_subm.errors.length > 0

        topic_deadline_rev = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(due_date['t_id'].to_i, topic_deadline_type_rev,i)
        topic_deadline_rev.update_attributes({'due_at' => due_date['review_' + i.to_s]})
        flash[:error] = "Please enter a valid Review deadline " + (i > 1 ? (i-1).to_s : "") if topic_deadline_rev.errors.length > 0
      end

      topic_deadline_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id(due_date['t_id'], DeadlineType.find_by_name('metareview').id)
      topic_deadline_subm.update_attributes({'due_at' => due_date['submission_' + (review_rounds+1).to_s]})
      flash[:error] = "Please enter a valid Meta review deadline" if topic_deadline_subm.errors.length > 0
    }

    redirect_to_sign_up(params[:assignment_id])
  end

  #used by save_topic_dependencies. The dependency graph is a partial ordering of topics ... some topics need to be done
  # before others can be attempted.
  def build_dependency_graph(topics,node)
    dg = RGL::DirectedAdjacencyGraph.new

    #create a graph of the assignment with appropriate dependency
    topics.collect { |topic|
      topic[1].each { |dependent_node|
        edge = Array.new
        #if a topic is not dependent on any other topic
        dependent_node = dependent_node.to_i
        if dependent_node == 0
          edge.push("fake")
        else
          #if we want the topic names to be displayed in the graph replace node to topic_name
          edge.push(SignUpTopic.find(dependent_node)[node])
        end
        edge.push(SignUpTopic.find(topic[0])[node])
        dg.add_edges(edge)
      }
    }
    #remove the fake vertex
    dg.remove_vertex("fake")
    dg
  end
  #used by save_topic_dependencies. Do not know how this works
  def create_common_start_time_topics(dg)
    dg_reverse = dg.clone.reverse()
    set_of_topics = Array.new

    while !dg_reverse.empty?
      i = 0
      temp_vertex_array = Array.new
      dg_reverse.each_vertex { |vertex|
        if dg_reverse.out_degree(vertex) == 0
          temp_vertex_array.push(vertex)
        end
      }
      #this cannot go inside the if statement above
      temp_vertex_array.each { |vertex|
        dg_reverse.remove_vertex(vertex)
      }
      set_of_topics.insert(i, temp_vertex_array)
      i = i + 1
    end
    set_of_topics
  end

  def create_topic_deadline(due_date, offset, topic_id)
    topic_deadline = TopicDeadline.new
    topic_deadline.topic_id = topic_id
    topic_deadline.due_at = DateTime.parse(due_date.due_at.to_s) + offset.to_i
    topic_deadline.deadline_type_id = due_date.deadline_type_id
    topic_deadline.late_policy_id = due_date.late_policy_id
    topic_deadline.submission_allowed_id = due_date.submission_allowed_id
    topic_deadline.review_allowed_id = due_date.review_allowed_id
    topic_deadline.resubmission_allowed_id = due_date.resubmission_allowed_id
    topic_deadline.rereview_allowed_id = due_date.rereview_allowed_id
    topic_deadline.review_of_review_allowed_id = due_date.review_of_review_allowed_id
    topic_deadline.round = due_date.round
    topic_deadline.save
  end

  def set_start_due_date(assignment_id, set_of_topics)

    #Remember, in create_common_start_time_topics function we reversed the graph so reverse it back
    set_of_topics = set_of_topics.reverse

    set_of_topics_due_dates = Array.new
    i=0
    days_between_submissions = Assignment.find(assignment_id)['days_between_submissions'].to_i
    set_of_topics.each { |set_of_topic|
      set_of_due_dates = nil
      if i==0
        #take the first set from the table which user stores
        set_of_due_dates = DueDate.find_all_by_assignment_id(assignment_id)
        offset = 0
      else
        set_of_due_dates = TopicDeadline.find_all_by_topic_id(set_of_topics[i-1][0])

        set_of_due_dates.sort! { |a, b| a.due_at <=> b.due_at }

        offset = days_between_submissions
      end

      set_of_topic.each { |topic_id|
        #if the due dates have already been created and the save dependency is being clicked,
        #then delete existing n create again
        prev_saved_due_dates = TopicDeadline.find_all_by_topic_id(topic_id)

        #Only if there is a dependency for the topic
        if !prev_saved_due_dates.nil?
          num_due_dates = prev_saved_due_dates.length
          #for each due date in the current topic he want to compare it to the previous due date
          for x in 0..num_due_dates - 1
            #we don't want the old date to move earlier in time so we save it as the new due date and destroy the old one  
            if DateTime.parse(set_of_due_dates[x].due_at.to_s) + offset.to_i < DateTime.parse(prev_saved_due_dates[x].due_at.to_s)
              set_of_due_dates[x] = prev_saved_due_dates[x]
              offset = 0
            end
            prev_saved_due_dates[x].destroy
          end
        end

        set_of_due_dates.each { |due_date|
          create_topic_deadline(due_date, offset, topic_id)
        }
      }
      i = i+1
    }

  end

  #gets team_details to show it on team_details view for a given assignment
  def team_details
    if !(assignment = Assignment.find(params[:assignment_id])).nil? and !(topic = SignUpTopic.find(params[:id])).nil?
      @results =ad_info(assignment.id, topic.id)
      @results.each do |result|
        result.attributes().each do |attr|
          if attr[0].equal? "name"
            @current_team_name = attr[1]
          end
        end
      end
      @results.each { |result|
        @team_members = ""
        TeamsUser.find_all_by_team_id(result[:team_id]).each { |teamuser|
          puts 'Userblaahsdb asd' +User.find(teamuser.user_id).to_json
          @team_members+=User.find(teamuser.user_id).name+" "
        }
      }
      #@team_members = find_team_members(topic)  
    end
  end

  # searches and returns team members for a given team_id
  def find_team_members(team_id)
    TeamsUser.find_all_by_team_id(team_id).each { |teamuser|
      team_members+=User.find(teamuser.user_id).handle+" "
    }
  end

  # get info related to the ad for partners so that it can be displayed when an assignment_participant
  # clicks to see ads related to a topic
  def ad_info(assignment_id, topic_id)
    query = "select t.id as team_id,t.comments_for_advertisement,t.name,su.assignment_id from teams t, signed_up_users s,sign_up_topics su where s.topic_id='"+topic_id.to_s+"' and s.creator_id=t.id and s.topic_id = su.id;    "
    SignUpTopic.find_by_sql(query)
  end

  def create_default_for_microtask
    assignment_id = params[:id]
    @sign_up_topic = SignUpTopic.new
    @sign_up_topic.topic_identifier = 'MT1'
    @sign_up_topic.topic_name = 'Microtask Topic'
    @sign_up_topic.max_choosers = '0'
    @sign_up_topic.micropayment = 0
    @sign_up_topic.assignment_id = assignment_id

    @assignment = Assignment.find(params[:id])

=begin
    if @assignment.staggered_deadline?
      topic_set = Array.new
      topic = @sign_up_topic.id

    end
=end

    if @sign_up_topic.save

      flash[:notice] = 'Default Microtask topic was created - please update.'
      redirect_to_sign_up(assignment_id)
    else
      render :action => 'new', :id => assignment_id
    end
  end


end