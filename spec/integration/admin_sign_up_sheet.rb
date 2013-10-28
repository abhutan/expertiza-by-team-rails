require 'spec/spec_helper'

describe 'add_sign_up_topic' do

  it 'should add sign up topics' do

    visit '/'
    page.should have_content('Welcome to Expertiza')
    within("#session") do
      fill_in 'Login', :with => 'admin'
      fill_in 'Password', :with => 'expertiza'
    end
  end
end