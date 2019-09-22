
class WorldwidePolicy < DatabasePolicy

  def update?
    false
  end

  def destroy?
    false
  end

  def index_association? association
    return false if association == :registrations
    return user.administrator?
  end

  def new_association? association
    user.administrator? && %i[countries local_areas managers].include?(association)
  end

  def destroy_association? association = nil
    user.administrator? && %i[countries local_areas].include?(association)
  end

end
