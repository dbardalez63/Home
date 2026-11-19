using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FamiliaRodriguez.Genealogy;

public static class GedcomParser
{
    private static readonly Regex RecordStart = new(@"^0 @(?<id>[^@]+)@ (?<tag>\w+)", RegexOptions.Compiled);
    private static readonly Regex NameParts = new(@"^(?<givn>.*?)\s*/(?<surn>.*?)/\s*$", RegexOptions.Compiled);

    public static FamilyTreeSnapshot Parse(string gedcomText, string? preferredFocusName = null)
    {
        var lines = gedcomText.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var people = new Dictionary<string, PersonBuilder>(StringComparer.OrdinalIgnoreCase);
        var families = new Dictionary<string, FamilyBuilder>(StringComparer.OrdinalIgnoreCase);

        string? currentId = null;
        string? currentTag = null;
        string? eventContext = null;

        foreach (var raw in lines)
        {
            if (string.IsNullOrWhiteSpace(raw))
            {
                continue;
            }

            var line = raw.TrimEnd();
            var match = RecordStart.Match(line);
            if (match.Success)
            {
                currentId = match.Groups["id"].Value;
                currentTag = match.Groups["tag"].Value;
                eventContext = null;

                if (currentTag == "INDI")
                {
                    people[currentId] = new PersonBuilder { Id = currentId };
                }
                else if (currentTag == "FAM")
                {
                    families[currentId] = new FamilyBuilder { Id = currentId };
                }

                continue;
            }

            if (currentId is null || currentTag is null)
            {
                continue;
            }

            if (!TrySplitLevel(line, out var level, out var tag, out var value))
            {
                continue;
            }

            if (currentTag == "INDI" && people.TryGetValue(currentId, out var person))
            {
                ApplyIndividual(person, level, tag, value, ref eventContext);
            }
            else if (currentTag == "FAM" && families.TryGetValue(currentId, out var family))
            {
                ApplyFamily(family, level, tag, value, ref eventContext);
            }
        }

        // Enrich empty surnames from parental family when possible
        foreach (var person in people.Values.Where(p => p.NeedsSurnameHint))
        {
            if (person.FamilyAsChildId is null || !families.TryGetValue(person.FamilyAsChildId, out var fam))
            {
                continue;
            }

            var father = fam.HusbandId is not null && people.TryGetValue(fam.HusbandId, out var dad) ? dad : null;
            var mother = fam.WifeId is not null && people.TryGetValue(fam.WifeId, out var mom) ? mom : null;
            var hint = BuildCompoundSurname(father?.Surname, mother?.Surname);
            if (!string.IsNullOrWhiteSpace(hint))
            {
                person.Surname ??= hint;
                person.FullName = string.IsNullOrWhiteSpace(person.GivenName)
                    ? hint
                    : $"{person.GivenName} {hint}".Trim();
            }
        }

        var peopleMap = people.Values
            .Select(p => p.ToPerson())
            .ToDictionary(p => p.Id, StringComparer.OrdinalIgnoreCase);

        var familyList = families.Values
            .Select(f => f.ToFamily())
            .ToList();

        var focusId = ResolveFocus(peopleMap, preferredFocusName)
            ?? peopleMap.Keys.FirstOrDefault()
            ?? "unknown";

        return new FamilyTreeSnapshot
        {
            People = peopleMap,
            Families = familyList,
            FocusPersonId = focusId,
            SourceName = "Ancestry — Maria Adela Rodriguez"
        };
    }

    private static void ApplyIndividual(PersonBuilder person, int level, string tag, string value, ref string? eventContext)
    {
        if (level == 1)
        {
            eventContext = tag is "BIRT" or "DEAT" or "BURI" ? tag : null;

            switch (tag)
            {
                case "NAME" when string.IsNullOrWhiteSpace(person.FullName):
                    ApplyName(person, value);
                    break;
                case "SEX":
                    person.Sex = value.Trim().ToUpperInvariant() switch
                    {
                        "M" => PersonSex.Male,
                        "F" => PersonSex.Female,
                        _ => PersonSex.Unknown
                    };
                    break;
                case "FAMC" when person.FamilyAsChildId is null:
                    person.FamilyAsChildId = StripId(value);
                    break;
                case "FAMS":
                    var fams = StripId(value);
                    if (!string.IsNullOrWhiteSpace(fams))
                    {
                        person.FamilyAsSpouseIds.Add(fams);
                    }
                    break;
            }

            return;
        }

        if (level == 2 && eventContext is not null)
        {
            switch (tag)
            {
                case "DATE":
                    if (eventContext == "BIRT" && person.BirthDate is null)
                    {
                        person.BirthDate = NormalizeDate(value);
                    }
                    else if (eventContext == "DEAT" && person.DeathDate is null)
                    {
                        person.DeathDate = NormalizeDate(value);
                    }
                    break;
                case "PLAC":
                    if (eventContext == "BIRT" && person.BirthPlace is null)
                    {
                        person.BirthPlace = value.Trim();
                    }
                    else if (eventContext == "DEAT" && person.DeathPlace is null)
                    {
                        person.DeathPlace = value.Trim();
                    }
                    break;
            }
        }
    }

    private static void ApplyFamily(FamilyBuilder family, int level, string tag, string value, ref string? eventContext)
    {
        if (level == 1)
        {
            eventContext = tag == "MARR" ? "MARR" : null;
            switch (tag)
            {
                case "HUSB":
                    family.HusbandId = StripId(value);
                    break;
                case "WIFE":
                    family.WifeId = StripId(value);
                    break;
                case "CHIL":
                    var child = StripId(value);
                    if (!string.IsNullOrWhiteSpace(child) && !family.ChildrenIds.Contains(child, StringComparer.OrdinalIgnoreCase))
                    {
                        family.ChildrenIds.Add(child);
                    }
                    break;
            }

            return;
        }

        if (level == 2 && eventContext == "MARR")
        {
            if (tag == "DATE" && family.MarriageDate is null)
            {
                family.MarriageDate = NormalizeDate(value);
            }
            else if (tag == "PLAC" && family.MarriagePlace is null)
            {
                family.MarriagePlace = value.Trim();
            }
        }
    }

    private static void ApplyName(PersonBuilder person, string value)
    {
        var cleaned = value.Trim();
        var match = NameParts.Match(cleaned);
        if (match.Success)
        {
            person.GivenName = match.Groups["givn"].Value.Trim();
            person.Surname = match.Groups["surn"].Value.Trim();
            person.FullName = string.Join(" ", new[] { person.GivenName, person.Surname }.Where(s => !string.IsNullOrWhiteSpace(s)));
            person.NeedsSurnameHint = string.IsNullOrWhiteSpace(person.Surname);
        }
        else
        {
            person.FullName = cleaned.Replace("/", " ").Trim();
            person.NeedsSurnameHint = !cleaned.Contains('/');
        }
    }

    private static string? ResolveFocus(IReadOnlyDictionary<string, Person> people, string? preferredFocusName)
    {
        if (!string.IsNullOrWhiteSpace(preferredFocusName))
        {
            var hit = people.Values.FirstOrDefault(p =>
                p.FullName.Contains(preferredFocusName, StringComparison.OrdinalIgnoreCase));
            if (hit is not null)
            {
                return hit.Id;
            }
        }

        return people.Values
            .FirstOrDefault(p => p.FullName.Contains("María Adela", StringComparison.OrdinalIgnoreCase)
                || p.FullName.Contains("Maria Adela", StringComparison.OrdinalIgnoreCase))
            ?.Id;
    }

    private static string? BuildCompoundSurname(string? fatherSurname, string? motherSurname)
    {
        var f = FirstSurnameToken(fatherSurname);
        var m = FirstSurnameToken(motherSurname);
        if (f is null && m is null)
        {
            return null;
        }

        if (f is null)
        {
            return m;
        }

        if (m is null)
        {
            return f;
        }

        return $"{f} {m}";
    }

    private static string? FirstSurnameToken(string? surname)
    {
        if (string.IsNullOrWhiteSpace(surname))
        {
            return null;
        }

        return surname.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
    }

    private static string NormalizeDate(string value)
    {
        var text = value.Trim();
        text = text.Replace("Ago", "Aug", StringComparison.OrdinalIgnoreCase)
            .Replace("Dic", "Dec", StringComparison.OrdinalIgnoreCase)
            .Replace("Sept", "Sep", StringComparison.OrdinalIgnoreCase);

        string[] formats =
        [
            "d MMM yyyy", "dd MMM yyyy", "d MMMM yyyy", "dd MMMM yyyy",
            "MMM yyyy", "yyyy"
        ];

        if (DateTime.TryParseExact(text, formats, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var dt))
        {
            return dt.ToString("d MMM yyyy", CultureInfo.GetCultureInfo("es-ES"));
        }

        return value.Trim();
    }

    private static string StripId(string value) =>
        value.Trim().Trim('@');

    private static bool TrySplitLevel(string line, out int level, out string tag, out string value)
    {
        level = 0;
        tag = "";
        value = "";

        var parts = line.Split(' ', 3, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || !int.TryParse(parts[0], out level))
        {
            return false;
        }

        tag = parts[1];
        value = parts.Length > 2 ? parts[2] : "";
        return true;
    }

    private sealed class PersonBuilder
    {
        public required string Id { get; init; }
        public string FullName { get; set; } = "";
        public string? GivenName { get; set; }
        public string? Surname { get; set; }
        public string? BirthDate { get; set; }
        public string? DeathDate { get; set; }
        public string? BirthPlace { get; set; }
        public string? DeathPlace { get; set; }
        public PersonSex Sex { get; set; } = PersonSex.Unknown;
        public string? FamilyAsChildId { get; set; }
        public List<string> FamilyAsSpouseIds { get; } = [];
        public bool NeedsSurnameHint { get; set; }

        public Person ToPerson() => new()
        {
            Id = Id,
            FullName = string.IsNullOrWhiteSpace(FullName) ? Id : FullName,
            BirthDate = BirthDate,
            DeathDate = DeathDate,
            BirthPlace = BirthPlace,
            DeathPlace = DeathPlace,
            Sex = Sex,
            FamilyAsChildId = FamilyAsChildId,
            FamilyAsSpouseIds = FamilyAsSpouseIds.ToList(),
            Notes = $"Ancestry ID {Id}"
        };
    }

    private sealed class FamilyBuilder
    {
        public required string Id { get; init; }
        public string? HusbandId { get; set; }
        public string? WifeId { get; set; }
        public string? MarriageDate { get; set; }
        public string? MarriagePlace { get; set; }
        public List<string> ChildrenIds { get; } = [];

        public FamilyUnit ToFamily() => new()
        {
            Id = Id,
            HusbandId = HusbandId,
            WifeId = WifeId,
            MarriageDate = MarriageDate,
            MarriagePlace = MarriagePlace,
            ChildrenIds = ChildrenIds.ToList()
        };
    }
}
