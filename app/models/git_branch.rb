class GitBranch
  INVALID_COMPONENT = /[\000-\040\177~^:?*\[\\]/

  def self.valid?(value)
    value.is_a?(String) && value.present? && value != "@" && !value.start_with?("-", "/") &&
      !value.end_with?(".", "/") && !value.include?("..") && !value.include?("@{") &&
      value.split("/", -1).all? do |component|
        component.present? && !component.start_with?(".") && !component.end_with?(".lock") &&
          !component.match?(INVALID_COMPONENT)
      end
  end
end
