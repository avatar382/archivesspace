class ResourcesController <  ApplicationController
  include ResultInfo
  helper_method :process_repo_info
  helper_method :process_subjects
  helper_method :process_agents

  include TreeApis

  skip_before_filter  :verify_authenticity_token


  DEFAULT_RES_FACET_TYPES = %w{primary_type subjects agents}
  
  DEFAULT_RES_INDEX_OPTS = {
    'resolve[]' => ['repository:id',  'resource:id@compact_resource'],
    'sort' => 'title_sort asc',
    'facet.mincount' => 1
  }

  DEFAULT_RES_SEARCH_OPTS = {
    'resolve[]' => ['repository:id',  'resource:id@compact_resource', 'ancestors:id@compact_resource'],
    'facet.mincount' => 1
  }

  DEFAULT_RES_SEARCH_PARAMS = {
    :q => ['*'],
    :limit => 'resource',
    :op => [''],
    :field => ['title']
  }
  DEFAULT_RES_TYPES = %w{pui_archival_object pui_digital_object agent subject}

  # present a list of resources.  If no repository named, just get all of them.
  def index
    @repo_name = params[:repo] || ""
    @repo_id = params.fetch(:rid, nil)
    if @repo_id
      @base_search =  "/repositories/#{@repo_id}/resources?"
    else
      @base_search = "/repositories/resources?"
    end
    search_opts = default_search_opts( DEFAULT_RES_INDEX_OPTS)
    search_opts['fq'] = ["repository:\"/repositories/#{@repo_id}\""] if @repo_id
    DEFAULT_RES_SEARCH_PARAMS.each do |k,v|
      params[k] = v unless params.fetch(k, nil)
    end
    page = Integer(params.fetch(:page, "1"))
    facet_types = DEFAULT_RES_FACET_TYPES
    facet_types.unshift('repository') if !@repo_id
    begin
      set_up_and_run_search(['resource'], facet_types,search_opts, params)
    rescue Exception => error
      flash[:error] = error
      redirect_back(fallback_location: '/' ) and return
    end
    @context = repo_context(@repo_id, 'resource')
     unless @pager.one_page?
        @search[:dates_within] = true if params.fetch(:filter_from_year,'').blank? && params.fetch(:filter_to_year,'').blank?
        @search[:text_within] = true
      end
    @page_title = I18n.t('resource._plural')
    @results_type = @page_title
    @sort_opts = []
    all_sorts = Search.get_sort_opts
    all_sorts.delete('relevance') unless params[:q].size > 1 || params[:q] != '*'
    all_sorts.keys.each do |type|
       @sort_opts.push(all_sorts[type])
    end

    if params[:q].size > 1 || params[:q][0] != '*'
      @sort_opts.unshift(all_sorts['relevance'])
    end
    @no_statement = true
#    if @results['results'].length == 1
#      @result =  @results['results'][0]
#      render 'resources/show'
#    else
      render 'search/search_results'
#    end
  end

  def search 
    repo_id = params.require(:repo_id)
    res_id = "/repositories/#{repo_id}/resources/#{params.require(:id)}"
    search_opts = DEFAULT_RES_SEARCH_OPTS
    search_opts['fq'] = ["resource:\"#{res_id}\""]
    params[:res_id] = res_id
#    q = params.fetch(:q,'')
    unless params.fetch(:q,nil)
      params[:q] = ['*']
    end
    @base_search = "#{res_id}/search?"
    begin
      set_up_advanced_search(DEFAULT_RES_TYPES, DEFAULT_RES_FACET_TYPES, search_opts, params)
    rescue Exception => error
      flash[:error] = error
      redirect_back(fallback_location: res_id ) and return
    end

    page = Integer(params.fetch(:page, "1"))
    @results = archivesspace.advanced_search('/search',page, @criteria)
    if @results['total_hits'].blank? ||  @results['total_hits'] == 0
      flash[:notice] = I18n.t('search_results.no_results')
      redirect_back(fallback_location: @base_search)
    else
      process_search_results(@base_search)
      title = ''
      title =  strip_mixed_content(@results['results'][0]['_resolved_resource']['json']['title']) if @results['results'][0] &&  @results['results'][0].dig('_resolved_resource', 'json')
       
      @context = []
      @context.push({:uri => "/repositories/#{repo_id}", 
                      :crumb => get_pretty_facet_value('repository', "/repositories/#{repo_id}")})
      unless title.blank?
        @context.push({:uri => "#{res_id}", :crumb => title})
      end
     unless @pager.one_page?
        @search[:dates_within] = true if params.fetch(:filter_from_year,'').blank? && params.fetch(:filter_to_year,'').blank?
        @search[:text_within] = true
      end
      @page_title = I18n.t('actions.search_in', :type => (title.blank? ? I18n.t('resource._singular') : "\"#{title}\""))
      @sort_opts = []
      all_sorts = Search.get_sort_opts
      all_sorts.delete('relevance') unless params[:q].size > 1 || params[:q] != '*'
      all_sorts.keys.each do |type|
        @sort_opts.push(all_sorts[type])
      end
      @no_statement = true
# Pry::ColorPrinter.pp @results['results'][0]['_resolved_resource']['json']
      render 'search/search_results'
    end
  end
  def show
    uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"
    begin
      @criteria = {}
      @criteria['resolve[]']  = ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'related_accession_uris:id']
      @result =  archivesspace.get_record(uri, @criteria)
      @repo_info = @result.repository_information
      @page_title = "#{I18n.t('resource._singular')}: #{strip_mixed_content(@result.display_string)}"
      @context = [{:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name']}, {:uri => nil, :crumb => process_mixed_content(@result.display_string)}]
#      @rep_image = get_rep_image(@result['json']['instances'])
      fill_request_info(true)
      # GONE # @tree = fetch_tree(uri)
    rescue RecordNotFound
      @type = I18n.t('resource._singular')
      @page_title = I18n.t('errors.error_404', :type => @type)
      @uri = uri
      @back_url = request.referer || ''
      render  'shared/not_found'
    end
  end

  def infinite
    @root_uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"
    begin
      @criteria = {}
      @criteria['resolve[]']  = ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'related_accession_uris:id']
      @result =  archivesspace.get_record(@root_uri, @criteria)
      @repo_info = @result.repository_information
      @page_title = "#{I18n.t('resource._singular')}: #{strip_mixed_content(@result.display_string)}"
      @context = [{:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name']}, {:uri => nil, :crumb => process_mixed_content(@result.display_string)}]
      fill_request_info(true)
      @ordered_records = archivesspace.get_record(@root_uri + '/ordered_records').json.fetch('uris')
    rescue RecordNotFound
      @type = I18n.t('resource._singular')
      @page_title = I18n.t('errors.error_404', :type => @type)
      @uri = @root_uri
      @back_url = request.referer || ''
      render  'shared/not_found'
    end
  end

  def waypoints
    results = archivesspace.search_records(params[:urls], {}, true)

    render :json => Hash[results.records.map {|record|
                           @result = record
                           [record.uri,
                            render_to_string(:partial => 'infinite_item')]}]
  end

  def tree_root
    @root_uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"

    render :json => archivesspace.get_raw_record(@root_uri + '/tree/root')
  end

  def tree_node
    @root_uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"

    render :json => archivesspace.get_raw_record(@root_uri + '/tree/node_' + params[:node])
  end

  def tree_waypoint
    @root_uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"

    render :json => archivesspace.get_raw_record(@root_uri + '/tree/waypoint_' + params[:node] + '_' + params[:offset])
  end

  def tree_node_from_root
    @root_uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"

    render :json => archivesspace.get_raw_record(@root_uri + '/tree/node_from_root_' + params[:node_ids].first)
  end

  def inventory
    uri = "/repositories/#{params[:rid]}/resources/#{params[:id]}"
    begin
      # stuff for the collection bits
      @criteria = {}
      @criteria['resolve[]']  = ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'related_accession_uris:id']
      @result =  archivesspace.get_record(uri, @criteria)
      @repo_info = @result.repository_information
      @page_title = "#{I18n.t('resource._singular')}: #{strip_mixed_content(@result.display_string)}"
      @context = [{:uri => @repo_info['top']['uri'], :crumb => @repo_info['top']['name']}, {:uri => nil, :crumb => process_mixed_content(@result.display_string)}]
      fill_request_info(true)

      # top container stuff ... sets @records
      fetch_containers(uri, "#{uri}/inventory", params)

      if !@results.blank?
        params[:q] = '*'
        @pager =  Pager.new(@base_search, @results['this_page'], @results['last_page'])
      else
        @pager = nil
      end

    rescue RecordNotFound
      @type = I18n.t('resource._singular')
      @page_title = I18n.t('errors.error_404', :type => @type)
      @uri = uri
      @back_url = request.referer || ''
      render  'shared/not_found'
    end
  end


  private

  def fetch_containers(resource_uri, page_uri, params)
    qry = "collection_uri_u_sstr:\"#{resource_uri}\" AND types:pui AND types:pui_container"
    @base_search = "#{page_uri}?"
    search_opts =  default_search_opts({
      'sort' => 'typeahead_sort_key_u_sort asc',
      'facet.mincount' => 1
    })
    search_opts['fq']=[qry]
    set_up_search(['pui_container'], ['type_enum_s', 'series_title_u_sstr'], search_opts, params, qry)
    @base_search= @base_search.sub("q=#{qry}", '')
    page = Integer(params.fetch(:page, "1"))

    @results = archivesspace.search(@query, page, @criteria)

    if @results['total_hits'] > 0
      process_search_results(@base_search)
    else
      @results = []
    end
  end

end