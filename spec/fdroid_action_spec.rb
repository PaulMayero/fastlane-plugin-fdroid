describe Fastlane::Actions::FdroidAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The fdroid plugin is working!")

      Fastlane::Actions::FdroidAction.run(nil)
    end
  end
end
