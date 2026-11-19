namespace FamiliaRodriguez.Genealogy;

public enum PersonSex
{
    Male,
    Female,
    Unknown
}

public sealed class Person
{
    public required string Id { get; init; }
    public required string FullName { get; init; }
    public string? BirthDate { get; init; }
    public string? DeathDate { get; init; }
    public string? BirthPlace { get; init; }
    public string? DeathPlace { get; init; }
    public PersonSex Sex { get; init; }
    public string? Notes { get; init; }
    public string? FamilyAsChildId { get; init; }
    public List<string> FamilyAsSpouseIds { get; init; } = [];

    public string YearsDisplay
    {
        get
        {
            var birth = string.IsNullOrWhiteSpace(BirthDate) ? "?" : BirthDate;
            var death = string.IsNullOrWhiteSpace(DeathDate) ? null : DeathDate;
            return death is null ? $"{birth}–" : $"{birth}–{death}";
        }
    }
}

public sealed class FamilyUnit
{
    public required string Id { get; init; }
    public string? HusbandId { get; init; }
    public string? WifeId { get; init; }
    public string? MarriageDate { get; init; }
    public string? MarriagePlace { get; init; }
    public List<string> ChildrenIds { get; init; } = [];
}

public sealed class FamilyTreeSnapshot
{
    public required IReadOnlyDictionary<string, Person> People { get; init; }
    public required IReadOnlyList<FamilyUnit> Families { get; init; }
    public required string FocusPersonId { get; init; }
    public string SourceName { get; init; } = "Ancestry";
}

public sealed class TreeNode
{
    public required Person Person { get; init; }
    public Person? Spouse { get; set; }
    public List<TreeNode> Children { get; init; } = [];
}
