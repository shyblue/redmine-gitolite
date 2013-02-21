class GitoliteHookController < ApplicationController
  unloadable

  skip_before_filter :verify_authenticity_token, :check_if_login_required

  def index
    repository = find_repository
    render(:text => 'OK')
  end

  private

  def get_identifier
    identifier = params[:project_id]
    # TODO: Can obtain 'oldrev', 'newrev', 'refname', 'user' in POST params for further action if needed.
    raise ActiveRecord::RecordNotFound, "[Gitolite] Project identifier not specified" if identifier.nil?
    return identifier
  end

  def find_project
    identifier = get_identifier
    project = Project.find_by_identifier(identifier.downcase)
    raise ActiveRecord::RecordNotFound, "[Gitolite] No project found with identifier '#{identifier}'" if project.nil?
    return project
  end

  def find_repository
    project = find_project
    repository = project.repositories.select{|r| r.identifier == params[:repo_id]}.first
    raise TypeError, "[Gitolite] Project '#{project.to_s}' ('#{project.identifier}') has no repository identified by #{params[:repo_id]}" if repository.nil?
    raise TypeError, "[Gitolite] Repository identified by #{params[:repo_id]} for project '#{project.to_s}' ('#{project.identifier}') is not a Git repository" unless repository.is_a?(Repository::Git)
    return repository
  end

  def logger
    Rails.logger
  end
end
